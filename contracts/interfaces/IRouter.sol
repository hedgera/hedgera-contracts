// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRouter
 * @notice Interface for the Router contract
 */
interface IRouter {
    /**
     * @notice Swap exact USDC for multiple tokens according to allocations
     * @param totalUSDC Total USDC amount to spend
     * @param tokens Array of token addresses to buy
     * @param allocations Array of USDC amounts for each token
     * @param minAmounts Array of minimum token amounts to receive
     * @param recipient Address to receive the tokens
     * @return amounts Array of actual token amounts received
     */
    function swapExactUSDCForTokens(
        uint256 totalUSDC,
        address[] calldata tokens,
        uint256[] calldata allocations,
        uint256[] calldata minAmounts,
        address recipient
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swap exact tokens for USDC
     * @param tokens Array of token addresses to sell
     * @param amounts Array of token amounts to sell
     * @param minUSDCAmounts Array of minimum USDC amounts to receive
     * @param recipient Address to receive USDC
     * @return usdcAmounts Array of USDC amounts received
     */
    function swapExactTokensForUSDC(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata minUSDCAmounts,
        address recipient
    ) external returns (uint256[] memory usdcAmounts);

    /**
     * @notice Get output amounts for given input amount and path
     * @param amountIn Input amount
     * @param path Token swap path
     * @return amounts Output amounts
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Get input amounts for given output amount and path
     * @param amountOut Output amount
     * @param path Token swap path
     * @return amounts Input amounts
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Get token value in USDC
     * @param token Token address
     * @param amount Token amount
     * @return usdcValue Value in USDC
     */
    function getTokenValueInUSDC(address token, uint256 amount) external view returns (uint256 usdcValue);
} 