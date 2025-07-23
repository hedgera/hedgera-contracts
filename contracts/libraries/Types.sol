// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Types
 * @notice Library containing all data types used across the Hedgera protocol
 */
library Types {
    /**
     * @notice Status of an index
     */
    enum IndexStatus {
        Active,      // Index is active and can be minted/redeemed
        Inactive,    // Index is inactive but can still be redeemed
        Deprecated   // Index is deprecated and should not be used
    }

    /**
     * @notice Component token in an index basket
     */
    struct Component {
        address token;      // Token contract address
        uint256 weight;     // Weight in basis points (10000 = 100%)
        uint256 balance;    // Current balance of this token in vault
    }

    /**
     * @notice Fee configuration for an index
     */
    struct FeeConfig {
        uint256 mintFee;        // Mint fee in basis points
        uint256 redeemFee;      // Redeem fee in basis points
        uint256 platformShare;  // Platform's share of fees in basis points
    }

    /**
     * @notice Complete information about an index
     */
    struct IndexInfo {
        uint256 id;                 // Index ID
        string name;                // Index name
        string symbol;              // Index symbol
        address curator;            // Curator address
        address vault;              // Vault contract address
        address indexToken;         // Index token contract address
        uint256 creationTime;       // Block timestamp when created
        uint256 totalValueLocked;   // Total value locked in USDC
        uint256 totalVolume;        // Total trading volume in USDC
        IndexStatus status;         // Current status
        FeeConfig fees;             // Fee configuration
        Component[] components;     // Basket components
    }

    /**
     * @notice Mint operation details
     */
    struct MintParams {
        uint256 indexId;        // Index to mint
        uint256 minShares;      // Minimum shares to receive
        uint256 deadline;       // Transaction deadline
    }

    /**
     * @notice Redeem operation details
     */
    struct RedeemParams {
        uint256 indexId;        // Index to redeem from
        uint256 shares;         // Shares to redeem
        uint256 minAmount;      // Minimum USDC to receive
        uint256 deadline;       // Transaction deadline
        bool inKind;           // Whether to redeem in-kind (tokens) or cash (USDC)
    }

    /**
     * @notice Swap operation details for DEX interactions
     */
    struct SwapParams {
        address tokenIn;        // Input token address (USDC address for base currency)
        address tokenOut;       // Output token address (USDC address for base currency)
        uint256 amountIn;       // Input amount
        uint256 amountOutMin;   // Minimum output amount
        address to;             // Recipient address
        uint256 deadline;       // Transaction deadline
    }
} 