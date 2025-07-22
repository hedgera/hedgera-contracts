// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/Types.sol";

/**
 * @title IIndexRegistry
 * @notice Interface for the central registry of all indexes
 */
interface IIndexRegistry {
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
    ) external returns (uint256 indexId);

    /**
     * @notice Gets index information by ID
     * @param indexId The index ID
     * @return index The index information
     */
    function getIndex(uint256 indexId) external view returns (Types.IndexInfo memory index);

    /**
     * @notice Gets the total number of indexes
     * @return count Total number of indexes
     */
    function getIndexCount() external view returns (uint256 count);

    /**
     * @notice Updates index status
     * @param indexId The index ID
     * @param status New status
     */
    function updateIndexStatus(uint256 indexId, Types.IndexStatus status) external;

    /**
     * @notice Updates index addresses after deployment
     * @param indexId The index ID
     * @param vault Address of the deployed vault
     * @param token Address of the deployed index token
     */
    function updateIndexAddresses(uint256 indexId, address vault, address token) external;

    /**
     * @notice Updates index metrics (TVL, volume)
     * @param indexId The index ID
     * @param newTvl New total value locked
     * @param volumeToAdd Volume to add to total
     */
    function updateIndexMetrics(uint256 indexId, uint256 newTvl, uint256 volumeToAdd) external;

    // Events
    event IndexCreated(
        uint256 indexed indexId,
        string name,
        string symbol,
        address indexed curator,
        address[] tokens,
        uint256[] weights
    );

    event IndexStatusUpdated(uint256 indexed indexId, Types.IndexStatus status);
    
    event IndexAddressesUpdated(uint256 indexed indexId, address vault, address token);
    
    event IndexMetricsUpdated(uint256 indexed indexId, uint256 tvl, uint256 totalVolume);
} 