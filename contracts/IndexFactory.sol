// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IIndexRegistry.sol";
import "./IndexToken.sol";
import "./BasketVault.sol";
import "./libraries/Types.sol";

/**
 * @title IndexFactory
 * @notice Factory contract for creating new Hedgera indexes
 * @dev Orchestrates the deployment of IndexToken, BasketVault and registration
 */
contract IndexFactory is Ownable, ReentrancyGuard {
    /// @notice The registry contract
    IIndexRegistry public immutable registry;
    
    /// @notice The router contract address
    address public router;
    
    /// @notice USDC token address
    address public immutable usdc;
    
    /// @notice Index creation fee in USDC
    uint256 public indexCreationFee = 100e6; // 100 USDC
    
    /// @notice Minimum number of tokens required in an index
    uint256 public constant MIN_TOKENS = 2;
    
    /// @notice Maximum number of tokens allowed in an index
    uint256 public constant MAX_TOKENS = 10;
    
    /// @notice Minimum weight per token (basis points)
    uint256 public constant MIN_TOKEN_WEIGHT = 100; // 1%
    
    /// @notice Maximum weight per token (basis points)
    uint256 public constant MAX_TOKEN_WEIGHT = 5000; // 50%
    
    /// @notice Maximum total fees (mint + redeem)
    uint256 public constant MAX_TOTAL_FEES = 500; // 5%
    
    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Mapping to track authorized curators
    mapping(address => bool) public authorizedCurators;
    
    /// @notice Whether curator authorization is required
    bool public requireCuratorAuthorization = false;

    /**
     * @notice Constructor
     * @param registry_ Address of the IndexRegistry
     * @param usdc_ Address of the USDC token
     * @param owner_ Owner of the factory
     */
    constructor(
        address registry_,
        address usdc_,
        address owner_
    ) Ownable(owner_) {
        require(registry_ != address(0), "IndexFactory: registry cannot be zero");
        require(usdc_ != address(0), "IndexFactory: USDC cannot be zero");
        
        registry = IIndexRegistry(registry_);
        usdc = usdc_;
    }

    /**
     * @notice Creates a new index with all components
     * @param name Index name
     * @param symbol Index symbol
     * @param curator Address of the curator
     * @param tokens Array of token addresses in the basket
     * @param weights Array of weights for each token (basis points)
     * @param mintFee Mint fee in basis points
     * @param redeemFee Redeem fee in basis points
     * @return indexId The ID of the created index
     * @return vault Address of the deployed vault
     * @return indexToken Address of the deployed index token
     */
    function createIndex(
        string memory name,
        string memory symbol,
        address curator,
        address[] memory tokens,
        uint256[] memory weights,
        uint256 mintFee,
        uint256 redeemFee
    ) external nonReentrant returns (uint256 indexId, address vault, address indexToken) {
        // Validate inputs
        _validateIndexCreation(name, symbol, curator, tokens, weights, mintFee, redeemFee);
        
        // Check curator authorization if required
        if (requireCuratorAuthorization) {
            require(authorizedCurators[curator] || curator == msg.sender, "IndexFactory: curator not authorized");
        }
        
        // Collect creation fee if set
        if (indexCreationFee > 0) {
            IERC20(usdc).transferFrom(msg.sender, address(this), indexCreationFee);
        }

        // Create index in registry
        indexId = registry.createIndex(
            name,
            symbol,
            curator,
            tokens,
            weights,
            mintFee,
            redeemFee
        );

        // Deploy IndexToken
        indexToken = address(new IndexToken(
            name,
            symbol,
            indexId,
            address(this) // Factory is initial owner
        ));

        // Deploy BasketVault
        vault = address(new BasketVault(
            indexId,
            address(registry),
            usdc,
            address(this) // Factory is initial owner
        ));

        // Initialize components
        IndexToken(indexToken).initialize(vault);
        BasketVault(vault).initialize(indexToken, router);

        // Update registry with deployed addresses
        registry.updateIndexAddresses(indexId, vault, indexToken);

        // Transfer ownership to curator
        IndexToken(indexToken).transferOwnership(curator);
        BasketVault(vault).transferOwnership(curator);

        emit IndexCreated(
            indexId,
            name,
            symbol,
            curator,
            vault,
            indexToken,
            tokens,
            weights,
            msg.sender
        );

        return (indexId, vault, indexToken);
    }

    /**
     * @notice Sets the router address (owner only)
     * @param router_ New router address
     */
    function setRouter(address router_) external onlyOwner {
        require(router_ != address(0), "IndexFactory: router cannot be zero");
        router = router_;
        emit RouterUpdated(router_);
    }

    /**
     * @notice Updates the index creation fee (owner only)
     * @param newFee New creation fee in USDC
     */
    function updateIndexCreationFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000e6, "IndexFactory: fee too high"); // Max 1000 USDC
        indexCreationFee = newFee;
        emit IndexCreationFeeUpdated(newFee);
    }

    /**
     * @notice Sets curator authorization requirement (owner only)
     * @param required Whether curator authorization is required
     */
    function setRequireCuratorAuthorization(bool required) external onlyOwner {
        requireCuratorAuthorization = required;
        emit CuratorAuthorizationRequirementUpdated(required);
    }

    /**
     * @notice Adds an authorized curator (owner only)
     * @param curator Curator address to authorize
     */
    function addAuthorizedCurator(address curator) external onlyOwner {
        require(curator != address(0), "IndexFactory: curator cannot be zero");
        require(!authorizedCurators[curator], "IndexFactory: curator already authorized");
        
        authorizedCurators[curator] = true;
        emit CuratorAuthorized(curator);
    }

    /**
     * @notice Removes an authorized curator (owner only)
     * @param curator Curator address to remove
     */
    function removeAuthorizedCurator(address curator) external onlyOwner {
        require(authorizedCurators[curator], "IndexFactory: curator not authorized");
        
        authorizedCurators[curator] = false;
        emit CuratorDeauthorized(curator);
    }

    /**
     * @notice Withdraws collected fees (owner only)
     * @param to Address to send fees to
     * @param amount Amount to withdraw
     */
    function withdrawFees(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "IndexFactory: to cannot be zero");
        require(amount <= IERC20(usdc).balanceOf(address(this)), "IndexFactory: insufficient balance");
        
        IERC20(usdc).transfer(to, amount);
        emit FeesWithdrawn(to, amount);
    }

    /**
     * @notice Gets the collected fees balance
     * @return balance Current USDC balance
     */
    function getCollectedFees() external view returns (uint256 balance) {
        return IERC20(usdc).balanceOf(address(this));
    }

    /**
     * @notice Estimates the cost to create an index
     * @param tokens Array of token addresses
     * @param weights Array of weights
     * @return totalCost Total cost in USDC (creation fee + gas estimate)
     */
    function estimateIndexCreationCost(
        address[] memory tokens,
        uint256[] memory weights
    ) external view returns (uint256 totalCost) {
        // Basic validation
        require(tokens.length >= MIN_TOKENS, "IndexFactory: too few tokens");
        require(tokens.length <= MAX_TOKENS, "IndexFactory: too many tokens");
        require(tokens.length == weights.length, "IndexFactory: length mismatch");
        
        // Return creation fee (gas costs are dynamic)
        return indexCreationFee;
    }

    /**
     * @notice Checks if an address is an authorized curator
     * @param curator Address to check
     * @return authorized Whether the address is authorized
     */
    function isAuthorizedCurator(address curator) external view returns (bool authorized) {
        return authorizedCurators[curator];
    }

    /**
     * @notice Internal function to validate index creation parameters
     * @param name Index name
     * @param symbol Index symbol
     * @param curator Curator address
     * @param tokens Token addresses
     * @param weights Token weights
     * @param mintFee Mint fee
     * @param redeemFee Redeem fee
     */
    function _validateIndexCreation(
        string memory name,
        string memory symbol,
        address curator,
        address[] memory tokens,
        uint256[] memory weights,
        uint256 mintFee,
        uint256 redeemFee
    ) internal view {
        // Basic validations
        require(bytes(name).length > 0, "IndexFactory: name cannot be empty");
        require(bytes(symbol).length > 0, "IndexFactory: symbol cannot be empty");
        require(curator != address(0), "IndexFactory: curator cannot be zero");
        require(router != address(0), "IndexFactory: router not set");
        
        // Token validations
        require(tokens.length >= MIN_TOKENS, "IndexFactory: too few tokens");
        require(tokens.length <= MAX_TOKENS, "IndexFactory: too many tokens");
        require(tokens.length == weights.length, "IndexFactory: length mismatch");
        
        // Fee validations
        require(mintFee + redeemFee <= MAX_TOTAL_FEES, "IndexFactory: total fees too high");
        
        // Weight validations
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "IndexFactory: token cannot be zero");
            require(tokens[i] != usdc, "IndexFactory: cannot include USDC in basket");
            require(weights[i] >= MIN_TOKEN_WEIGHT, "IndexFactory: weight too low");
            require(weights[i] <= MAX_TOKEN_WEIGHT, "IndexFactory: weight too high");
            
            // Check for duplicate tokens
            for (uint256 j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], "IndexFactory: duplicate token");
            }
            
            totalWeight += weights[i];
        }
        require(totalWeight == BASIS_POINTS, "IndexFactory: weights must sum to 100%");
    }

    // Events
    event IndexCreated(
        uint256 indexed indexId,
        string name,
        string symbol,
        address indexed curator,
        address vault,
        address indexToken,
        address[] tokens,
        uint256[] weights,
        address indexed creator
    );

    event RouterUpdated(address indexed router);
    
    event IndexCreationFeeUpdated(uint256 fee);
    
    event CuratorAuthorizationRequirementUpdated(bool required);
    
    event CuratorAuthorized(address indexed curator);
    
    event CuratorDeauthorized(address indexed curator);
    
    event FeesWithdrawn(address indexed to, uint256 amount);
} 