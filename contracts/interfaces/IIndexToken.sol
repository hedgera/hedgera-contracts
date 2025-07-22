// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IIndexToken
 * @notice Interface for index tokens - ERC-20 tokens representing shares in an index
 */
interface IIndexToken is IERC20 {
    /**
     * @notice Mints new tokens (only callable by the associated vault)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns tokens (only callable by the associated vault)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Gets the associated vault address
     * @return vault Address of the vault that can mint/burn these tokens
     */
    function getVault() external view returns (address vault);

    /**
     * @notice Gets the index ID this token represents
     * @return indexId The index ID
     */
    function getIndexId() external view returns (uint256 indexId);

    /**
     * @notice Gets token metadata
     * @return name Token name
     * @return symbol Token symbol
     * @return decimals Token decimals
     */
    function getMetadata() external view returns (string memory name, string memory symbol, uint8 decimals);

    // Events (in addition to standard ERC-20 events)
    event VaultUpdated(address indexed oldVault, address indexed newVault);
} 