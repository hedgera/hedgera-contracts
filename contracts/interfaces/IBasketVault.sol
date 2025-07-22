// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/Types.sol";

/**
 * @title IBasketVault
 * @notice Interface for the basket vault that handles minting and redeeming of index tokens
 */
interface IBasketVault {
    /**
     * @notice Mints index tokens by depositing HBAR
     * @param minShares Minimum number of shares to receive
     * @param deadline Transaction deadline
     * @return shares Number of index token shares minted
     */
    function mint(uint256 minShares, uint256 deadline) external payable returns (uint256 shares);

    /**
     * @notice Redeems index tokens for HBAR
     * @param shares Number of shares to redeem
     * @param minAmount Minimum HBAR amount to receive
     * @param deadline Transaction deadline
     * @return amount Amount of HBAR received
     */
    function redeem(uint256 shares, uint256 minAmount, uint256 deadline) external returns (uint256 amount);

    /**
     * @notice Gets the current NAV (Net Asset Value) per share in HBAR
     * @return navPerShare NAV per share in wei
     */
    function getNavPerShare() external view returns (uint256 navPerShare);

    /**
     * @notice Gets the total value locked in the vault in HBAR
     * @return tvl Total value locked in wei
     */
    function getTotalValueLocked() external view returns (uint256 tvl);

    /**
     * @notice Gets the current basket composition
     * @return components Array of current component balances and weights
     */
    function getBasketComposition() external view returns (Types.Component[] memory components);

    /**
     * @notice Gets the index information this vault manages
     * @return indexId The index ID
     */
    function getIndexId() external view returns (uint256 indexId);

    /**
     * @notice Updates the basket weights (only callable by authorized addresses)
     * @param newWeights Array of new weights in basis points
     */
    function updateBasketWeights(uint256[] memory newWeights) external;

    /**
     * @notice Withdraws collected fees (only callable by owner)
     * @param to Address to send fees to
     * @param amount Amount of fees to withdraw
     */
    function withdrawFees(address to, uint256 amount) external;

    /**
     * @notice Gets the amount of fees collected
     * @return fees Amount of fees in HBAR
     */
    function getCollectedFees() external view returns (uint256 fees);

    // Events
    event Minted(
        address indexed user,
        uint256 indexed indexId,
        uint256 hbarIn,
        uint256 sharesOut,
        uint256 navPerShare
    );

    event Redeemed(
        address indexed user,
        uint256 indexed indexId,
        uint256 sharesIn,
        uint256 hbarOut,
        uint256 navPerShare
    );

    event FeesCollected(uint256 indexed indexId, uint256 amount, uint256 feeType);

    event BasketRebalanced(uint256 indexed indexId, uint256[] newWeights);

    event FeesWithdrawn(address indexed to, uint256 amount);
} 