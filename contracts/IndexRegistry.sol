// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IIndexRegistry.sol";
import "./libraries/Types.sol";

/**
 * @title IndexRegistry
 * @notice Central registry for all Hedgera indexes
 * @dev Stores metadata and manages the lifecycle of indexes
 */
contract IndexRegistry is Ownable, ReentrancyGuard, IIndexRegistry {
    /// @notice Current index ID counter
    uint256 private _indexCounter;
    
    /// @notice Mapping from index ID to index information
    mapping(uint256 => Types.IndexInfo) private _indexes;
    
    /// @notice Mapping to track authorized addresses (factories)
    mapping(address => bool) public authorizedFactories;
    
    /// @notice Maximum number of tokens allowed in an index
    uint256 public constant MAX_TOKENS_PER_INDEX = 10;
    
    /// @notice Maximum weight per token (basis points)
    uint256 public constant MAX_TOKEN_WEIGHT = 5000; // 50%
    
    /// @notice Minimum weight per token (basis points)
    uint256 public constant MIN_TOKEN_WEIGHT = 100; // 1%
    
    /// @notice Maximum total fee (mint + redeem)
    uint256 public constant MAX_TOTAL_FEE = 500; // 5%

    /**
     * @notice Constructor
     * @param owner_ Owner of the registry
     */
    constructor(address owner_) Ownable(owner_) {
        _indexCounter = 0;
    }

    /**
     * @notice Creates a new index
     * @param name Index name
     * @param symbol Index symbol
     * @param curator Address of the curator
     * @param tokens Array of token addresses in the basket
     * @param weights Array of weights for each token (basis points)
     * @param mintFee Mint fee in basis points
     * @param redeemFee Redeem fee in basis points
     * @return indexId The ID of the created index
     */
    function createIndex(
        string memory name,
        string memory symbol,
        address curator,
        address[] memory tokens,
        uint256[] memory weights,
        uint256 mintFee,
        uint256 redeemFee
    ) external override onlyAuthorized nonReentrant returns (uint256 indexId) {
        // Input validation
        require(bytes(name).length > 0, "IndexRegistry: name cannot be empty");
        require(bytes(symbol).length > 0, "IndexRegistry: symbol cannot be empty");
        require(curator != address(0), "IndexRegistry: curator cannot be zero address");
        require(tokens.length > 0, "IndexRegistry: must have at least one token");
        require(tokens.length <= MAX_TOKENS_PER_INDEX, "IndexRegistry: too many tokens");
        require(tokens.length == weights.length, "IndexRegistry: tokens and weights length mismatch");
        require(mintFee + redeemFee <= MAX_TOTAL_FEE, "IndexRegistry: total fees too high");

        // Validate weights and tokens
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "IndexRegistry: token cannot be zero address");
            require(weights[i] >= MIN_TOKEN_WEIGHT, "IndexRegistry: weight too low");
            require(weights[i] <= MAX_TOKEN_WEIGHT, "IndexRegistry: weight too high");
            
            // Check for duplicate tokens
            for (uint256 j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], "IndexRegistry: duplicate token");
            }
            
            totalWeight += weights[i];
        }
        require(totalWeight == 10000, "IndexRegistry: weights must sum to 100%");

        // Create new index
        indexId = _indexCounter++;
        
        Types.IndexInfo storage newIndex = _indexes[indexId];
        newIndex.id = indexId;
        newIndex.name = name;
        newIndex.symbol = symbol;
        newIndex.curator = curator;
        newIndex.creationTime = block.timestamp;
        newIndex.status = Types.IndexStatus.Active;
        newIndex.fees.mintFee = mintFee;
        newIndex.fees.redeemFee = redeemFee;
        newIndex.fees.platformShare = 5000; // 50% platform share by default

        // Add components
        for (uint256 i = 0; i < tokens.length; i++) {
            newIndex.components.push(Types.Component({
                token: tokens[i],
                weight: weights[i],
                balance: 0
            }));
        }

        emit IndexCreated(indexId, name, symbol, curator, tokens, weights);
        
        return indexId;
    }

    /**
     * @notice Gets index information by ID
     * @param indexId The index ID
     * @return index The index information
     */
    function getIndex(uint256 indexId) external view override returns (Types.IndexInfo memory index) {
        require(indexId < _indexCounter, "IndexRegistry: index does not exist");
        return _indexes[indexId];
    }

    /**
     * @notice Gets the total number of indexes
     * @return count Total number of indexes
     */
    function getIndexCount() external view override returns (uint256 count) {
        return _indexCounter;
    }

    /**
     * @notice Updates index status
     * @param indexId The index ID
     * @param status New status
     */
    function updateIndexStatus(uint256 indexId, Types.IndexStatus status) external override onlyAuthorized {
        require(indexId < _indexCounter, "IndexRegistry: index does not exist");
        
        _indexes[indexId].status = status;
        emit IndexStatusUpdated(indexId, status);
    }

    /**
     * @notice Updates index addresses after deployment
     * @param indexId The index ID
     * @param vault Address of the deployed vault
     * @param token Address of the deployed index token
     */
    function updateIndexAddresses(uint256 indexId, address vault, address token) external override onlyAuthorized {
        require(indexId < _indexCounter, "IndexRegistry: index does not exist");
        require(vault != address(0), "IndexRegistry: vault cannot be zero address");
        require(token != address(0), "IndexRegistry: token cannot be zero address");
        
        _indexes[indexId].vault = vault;
        _indexes[indexId].indexToken = token;
        
        emit IndexAddressesUpdated(indexId, vault, token);
    }

    /**
     * @notice Updates index metrics (TVL, volume)
     * @param indexId The index ID
     * @param newTvl New total value locked
     * @param volumeToAdd Volume to add to total
     */
    function updateIndexMetrics(uint256 indexId, uint256 newTvl, uint256 volumeToAdd) external override {
        require(indexId < _indexCounter, "IndexRegistry: index does not exist");
        
        // Allow either authorized factories or the index's own vault to update metrics
        require(
            authorizedFactories[msg.sender] || 
            msg.sender == owner() || 
            msg.sender == _indexes[indexId].vault,
            "IndexRegistry: not authorized"
        );
        
        _indexes[indexId].totalValueLocked = newTvl;
        _indexes[indexId].totalVolume += volumeToAdd;
        
        emit IndexMetricsUpdated(indexId, newTvl, _indexes[indexId].totalVolume);
    }

    /**
     * @notice Adds an authorized factory
     * @param factory Address of the factory to authorize
     */
    function addAuthorizedFactory(address factory) external onlyOwner {
        require(factory != address(0), "IndexRegistry: factory cannot be zero address");
        require(!authorizedFactories[factory], "IndexRegistry: factory already authorized");
        
        authorizedFactories[factory] = true;
    }

    /**
     * @notice Removes an authorized factory
     * @param factory Address of the factory to remove
     */
    function removeAuthorizedFactory(address factory) external onlyOwner {
        require(authorizedFactories[factory], "IndexRegistry: factory not authorized");
        
        authorizedFactories[factory] = false;
    }

    /**
     * @notice Gets all indexes (paginated)
     * @param offset Starting index
     * @param limit Number of indexes to return
     * @return indexes Array of index information
     */
    function getIndexes(uint256 offset, uint256 limit) 
        external 
        view 
        returns (Types.IndexInfo[] memory indexes) 
    {
        require(offset < _indexCounter, "IndexRegistry: offset out of bounds");
        
        uint256 end = offset + limit;
        if (end > _indexCounter) {
            end = _indexCounter;
        }
        
        indexes = new Types.IndexInfo[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            indexes[i - offset] = _indexes[i];
        }
        
        return indexes;
    }

    /**
     * @notice Gets indexes by curator
     * @param curator Curator address
     * @return indexIds Array of index IDs
     */
    function getIndexesByCurator(address curator) external view returns (uint256[] memory indexIds) {
        uint256 count = 0;
        
        // Count indexes by curator
        for (uint256 i = 0; i < _indexCounter; i++) {
            if (_indexes[i].curator == curator) {
                count++;
            }
        }
        
        // Populate array
        indexIds = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _indexCounter; i++) {
            if (_indexes[i].curator == curator) {
                indexIds[index] = i;
                index++;
            }
        }
        
        return indexIds;
    }

    /**
     * @notice Modifier to restrict access to authorized factories only
     */
    modifier onlyAuthorized() {
        require(authorizedFactories[msg.sender] || msg.sender == owner(), "IndexRegistry: not authorized");
        _;
    }
} 