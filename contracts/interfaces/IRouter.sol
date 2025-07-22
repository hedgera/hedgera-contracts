// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/Types.sol";

/**
 * @title IRouter
 * @notice Interface for DEX router integration (SaucerSwap on Hedera)
 */
interface IRouter {
    /**
     * @notice Swaps exact HBAR for tokens
     * @param amountOutMin Minimum amount of tokens to receive
     * @param path Array of token addresses for the swap path
     * @param to Address to receive the tokens
     * @param deadline Transaction deadline
     * @return amounts Array of amounts for each step in the path
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    /**
     * @notice Swaps exact tokens for HBAR
     * @param amountIn Amount of tokens to swap
     * @param amountOutMin Minimum amount of HBAR to receive
     * @param path Array of token addresses for the swap path
     * @param to Address to receive the HBAR
     * @param deadline Transaction deadline
     * @return amounts Array of amounts for each step in the path
     */
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Gets the amount of tokens that would be received for a given HBAR input
     * @param amountIn Amount of HBAR to swap
     * @param path Array of token addresses for the swap path
     * @return amounts Array of amounts for each step in the path
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Gets the amount of HBAR needed to receive a specific amount of tokens
     * @param amountOut Amount of tokens to receive
     * @param path Array of token addresses for the swap path
     * @return amounts Array of amounts for each step in the path
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Swaps HBAR for multiple tokens in specified proportions
     * @param tokens Array of token addresses to buy
     * @param weights Array of weights for each token (basis points)
     * @param minAmounts Array of minimum amounts for each token
     * @param deadline Transaction deadline
     * @return amounts Array of token amounts received
     */
    function swapETHForTokensProportional(
        address[] calldata tokens,
        uint256[] calldata weights,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    /**
     * @notice Swaps multiple tokens for HBAR
     * @param tokens Array of token addresses to sell
     * @param amounts Array of token amounts to sell
     * @param minETHAmount Minimum HBAR amount to receive
     * @param deadline Transaction deadline
     * @return ethAmount Amount of HBAR received
     */
    function swapTokensForETH(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256 minETHAmount,
        uint256 deadline
    ) external returns (uint256 ethAmount);

    /**
     * @notice Gets the SaucerSwap router address
     * @return router The SaucerSwap router address
     */
    function getSaucerSwapRouter() external view returns (address router);

    /**
     * @notice Gets the WHBAR (Wrapped HBAR) token address
     * @return whbar The WHBAR token address
     */
    function getWHBAR() external view returns (address whbar);

    // Events
    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event ProportionalSwapExecuted(
        address indexed user,
        uint256 hbarIn,
        address[] tokens,
        uint256[] amounts
    );
} 