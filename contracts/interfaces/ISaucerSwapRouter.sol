// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ISaucerSwapRouter
 * @notice Interface for SaucerSwap V1 router on Hedera (Uniswap V2-style)
 */
interface ISaucerSwapRouter {
    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible
     * @param amountIn The amount of input tokens to send
     * @param amountOutMin The minimum amount of output tokens that must be received
     * @param path An array of token addresses representing the swap path
     * @param to Recipient of the output tokens
     * @param deadline Unix timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible
     * @param amountOut The amount of output tokens to receive
     * @param amountInMax The maximum amount of input tokens that can be required
     * @param path An array of token addresses representing the swap path
     * @param to Recipient of the output tokens
     * @param deadline Unix timestamp after which the transaction will revert
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
     * @param amountIn The amount of input tokens
     * @param path An array of token addresses representing the swap path
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Given an output amount of an asset and pair reserves, returns a required input amount of the other asset
     * @param amountOut The amount of output tokens
     * @param path An array of token addresses representing the swap path
     * @return amounts The input token amount and all subsequent output token amounts
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
} 