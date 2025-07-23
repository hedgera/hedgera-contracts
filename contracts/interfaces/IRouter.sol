// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/Types.sol";

/**
 * @title IRouter
 * @notice Interface for DEX router integration (SaucerSwap on Hedera)
 */
interface IRouter {
    /**
     * @notice Swaps exact USDC for tokens
     * @param amountIn Amount of USDC to swap
     * @param amountOutMin Minimum amount of tokens to receive
     * @param path Array of token addresses for the swap path
     * @param to Address to receive the tokens
     * @param deadline Transaction deadline
     * @return amounts Array of amounts for each step in the path
     */
    function swapExactUSDCForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swaps exact tokens for USDC
     * @param amountIn Amount of tokens to swap
     * @param amountOutMin Minimum amount of USDC to receive
     * @param path Array of token addresses for the swap path
     * @param to Address to receive the USDC
     * @param deadline Transaction deadline
     * @return amounts Array of amounts for each step in the path
     */
    function swapExactTokensForUSDC(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Gets the amount of tokens that would be received for a given USDC input
     * @param amountIn Amount of USDC to swap
     * @param path Array of token addresses for the swap path
     * @return amounts Array of amounts for each step in the path
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Gets the amount of USDC needed to receive a specific amount of tokens
     * @param amountOut Amount of tokens to receive
     * @param path Array of token addresses for the swap path
     * @return amounts Array of amounts for each step in the path
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Swaps USDC for multiple tokens in specified proportions
     * @param usdcAmount Amount of USDC to swap
     * @param tokens Array of token addresses to buy
     * @param weights Array of weights for each token (basis points)
     * @param minAmounts Array of minimum amounts for each token
     * @param deadline Transaction deadline
     * @return amounts Array of token amounts received
     */
    function swapUSDCForTokensProportional(
        uint256 usdcAmount,
        address[] calldata tokens,
        uint256[] calldata weights,
        uint256[] calldata minAmounts,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swaps multiple tokens for USDC
     * @param tokens Array of token addresses to sell
     * @param amounts Array of token amounts to sell
     * @param minUSDCAmount Minimum USDC amount to receive
     * @param deadline Transaction deadline
     * @return usdcAmount Amount of USDC received
     */
    function swapTokensForUSDC(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256 minUSDCAmount,
        uint256 deadline
    ) external returns (uint256 usdcAmount);

    /**
     * @notice Gets the SaucerSwap router address
     * @return router The SaucerSwap router address
     */
    function getSaucerSwapRouter() external view returns (address router);

    /**
     * @notice Gets the USDC token address
     * @return usdc The USDC token address
     */
    function getUSDC() external view returns (address usdc);

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
        uint256 usdcIn,
        address[] tokens,
        uint256[] amounts
    );
} 