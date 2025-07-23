// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IRouter.sol";
import "./libraries/Types.sol";

/**
 * @title Router
 * @notice Router contract for DEX integration with SaucerSwap on Hedera
 * @dev Handles USDC-based swaps for index token operations
 */
contract Router is Ownable, ReentrancyGuard, IRouter {
    using SafeERC20 for IERC20;

    /// @notice SaucerSwap router address on Hedera
    address public saucerSwapRouter;
    
    /// @notice USDC token contract
    IERC20 public immutable usdc;
    
    /// @notice Maximum slippage allowed (basis points)
    uint256 public maxSlippage = 500; // 5%
    
    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /**
     * @notice Constructor
     * @param usdc_ USDC token address
     * @param saucerSwapRouter_ SaucerSwap router address
     * @param owner_ Owner of the contract
     */
    constructor(
        address usdc_,
        address saucerSwapRouter_,
        address owner_
    ) Ownable(owner_) {
        require(usdc_ != address(0), "Router: USDC cannot be zero");
        require(saucerSwapRouter_ != address(0), "Router: SaucerSwap router cannot be zero");
        
        usdc = IERC20(usdc_);
        saucerSwapRouter = saucerSwapRouter_;
    }

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
    ) external override nonReentrant returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Router: expired");
        require(amountIn > 0, "Router: amount must be positive");
        require(path.length >= 2, "Router: invalid path");
        require(path[0] == address(usdc), "Router: path must start with USDC");
        require(to != address(0), "Router: to cannot be zero");

        // Transfer USDC from caller
        usdc.safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve SaucerSwap router
        usdc.approve(saucerSwapRouter, amountIn);

        // For MVP: simulate swap (in production, would call SaucerSwap)
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        // Simplified conversion - in production would use actual SaucerSwap pricing
        uint256 outputAmount = _simulateSwap(amountIn, path[0], path[path.length - 1]);
        require(outputAmount >= amountOutMin, "Router: insufficient output amount");
        
        amounts[amounts.length - 1] = outputAmount;

        // Transfer output tokens to recipient
        IERC20(path[path.length - 1]).safeTransfer(to, outputAmount);

        emit SwapExecuted(msg.sender, path[0], path[path.length - 1], amountIn, outputAmount);

        return amounts;
    }

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
    ) external override nonReentrant returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Router: expired");
        require(amountIn > 0, "Router: amount must be positive");
        require(path.length >= 2, "Router: invalid path");
        require(path[path.length - 1] == address(usdc), "Router: path must end with USDC");
        require(to != address(0), "Router: to cannot be zero");

        // Transfer input tokens from caller
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve SaucerSwap router
        IERC20(path[0]).approve(saucerSwapRouter, amountIn);

        // For MVP: simulate swap
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        uint256 outputAmount = _simulateSwap(amountIn, path[0], path[path.length - 1]);
        require(outputAmount >= amountOutMin, "Router: insufficient output amount");
        
        amounts[amounts.length - 1] = outputAmount;

        // Transfer USDC to recipient
        usdc.safeTransfer(to, outputAmount);

        emit SwapExecuted(msg.sender, path[0], path[path.length - 1], amountIn, outputAmount);

        return amounts;
    }

    /**
     * @notice Gets the amount of tokens that would be received for a given USDC input
     * @param amountIn Amount of USDC to swap
     * @param path Array of token addresses for the swap path
     * @return amounts Array of amounts for each step in the path
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Router: invalid path");
        require(amountIn > 0, "Router: amount must be positive");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        // For MVP: simplified pricing
        for (uint256 i = 1; i < path.length; i++) {
            amounts[i] = _simulateSwap(amounts[i - 1], path[i - 1], path[i]);
        }

        return amounts;
    }

    /**
     * @notice Gets the amount of USDC needed to receive a specific amount of tokens
     * @param amountOut Amount of tokens to receive
     * @param path Array of token addresses for the swap path
     * @return amounts Array of amounts for each step in the path
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Router: invalid path");
        require(amountOut > 0, "Router: amount must be positive");

        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        // For MVP: simplified reverse pricing
        for (uint256 i = path.length - 1; i > 0; i--) {
            amounts[i - 1] = _simulateReverseSwap(amounts[i], path[i - 1], path[i]);
        }

        return amounts;
    }

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
    ) external override nonReentrant returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Router: expired");
        require(usdcAmount > 0, "Router: amount must be positive");
        require(tokens.length > 0, "Router: no tokens specified");
        require(tokens.length == weights.length, "Router: length mismatch");
        require(tokens.length == minAmounts.length, "Router: length mismatch");

        // Validate weights sum to 100%
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        require(totalWeight == BASIS_POINTS, "Router: weights must sum to 100%");

        // Transfer USDC from caller
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        amounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 allocation = (usdcAmount * weights[i]) / BASIS_POINTS;
            
            if (allocation > 0) {
                // Create swap path
                address[] memory path = new address[](2);
                path[0] = address(usdc);
                path[1] = tokens[i];

                // Perform swap
                usdc.approve(saucerSwapRouter, allocation);
                
                uint256 tokenAmount = _simulateSwap(allocation, address(usdc), tokens[i]);
                require(tokenAmount >= minAmounts[i], "Router: insufficient token amount");
                
                amounts[i] = tokenAmount;

                // Transfer tokens to caller
                IERC20(tokens[i]).safeTransfer(msg.sender, tokenAmount);
            }
        }

        emit ProportionalSwapExecuted(msg.sender, usdcAmount, tokens, amounts);

        return amounts;
    }

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
    ) external override nonReentrant returns (uint256 usdcAmount) {
        require(block.timestamp <= deadline, "Router: expired");
        require(tokens.length > 0, "Router: no tokens specified");
        require(tokens.length == amounts.length, "Router: length mismatch");

        usdcAmount = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                // Transfer tokens from caller
                IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);

                // Create swap path
                address[] memory path = new address[](2);
                path[0] = tokens[i];
                path[1] = address(usdc);

                // Perform swap
                IERC20(tokens[i]).approve(saucerSwapRouter, amounts[i]);
                
                uint256 usdcReceived = _simulateSwap(amounts[i], tokens[i], address(usdc));
                usdcAmount += usdcReceived;
            }
        }

        require(usdcAmount >= minUSDCAmount, "Router: insufficient USDC amount");

        // Transfer USDC to caller
        usdc.safeTransfer(msg.sender, usdcAmount);

        return usdcAmount;
    }

    /**
     * @notice Gets the SaucerSwap router address
     * @return router The SaucerSwap router address
     */
    function getSaucerSwapRouter() external view override returns (address) {
        return saucerSwapRouter;
    }

    /**
     * @notice Gets the USDC token address
     * @return The USDC token address
     */
    function getUSDC() external view override returns (address) {
        return address(usdc);
    }

    /**
     * @notice Updates the SaucerSwap router address (owner only)
     * @param newRouter New router address
     */
    function updateSaucerSwapRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0), "Router: router cannot be zero");
        require(newRouter != saucerSwapRouter, "Router: same router address");
        
        saucerSwapRouter = newRouter;
    }

    /**
     * @notice Updates the maximum slippage (owner only)
     * @param newMaxSlippage New maximum slippage in basis points
     */
    function updateMaxSlippage(uint256 newMaxSlippage) external onlyOwner {
        require(newMaxSlippage <= 1000, "Router: slippage too high"); // Max 10%
        maxSlippage = newMaxSlippage;
    }

    /**
     * @notice Emergency token recovery (owner only)
     * @param token Token address to recover
     * @param amount Amount to recover
     * @param to Address to send recovered tokens
     */
    function emergencyRecover(address token, uint256 amount, address to) external onlyOwner {
        require(to != address(0), "Router: to cannot be zero");
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Internal function to simulate a swap (MVP implementation)
     * @param amountIn Input amount
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return amountOut Output amount
     * @dev In production, this would call actual SaucerSwap pricing
     */
    function _simulateSwap(uint256 amountIn, address tokenIn, address tokenOut) 
        internal 
        view 
        returns (uint256 amountOut) 
    {
        // For MVP: simplified 1:1 conversion with small slippage
        // In production, would fetch real prices from SaucerSwap
        
        if (tokenIn == address(usdc)) {
            // USDC to token: assume 1 USDC = 1 token with 2% slippage
            amountOut = (amountIn * 9800) / 10000; // 2% slippage
        } else if (tokenOut == address(usdc)) {
            // Token to USDC: assume 1 token = 1 USDC with 2% slippage
            amountOut = (amountIn * 9800) / 10000; // 2% slippage
        } else {
            // Token to token: assume 1:1 with 3% slippage
            amountOut = (amountIn * 9700) / 10000; // 3% slippage
        }
        
        return amountOut;
    }

    /**
     * @notice Internal function to simulate reverse swap pricing
     * @param amountOut Desired output amount
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @return amountIn Required input amount
     */
    function _simulateReverseSwap(uint256 amountOut, address tokenIn, address tokenOut) 
        internal 
        view 
        returns (uint256 amountIn) 
    {
        // Reverse of _simulateSwap logic
        if (tokenIn == address(usdc)) {
            amountIn = (amountOut * 10000) / 9800; // Add 2% slippage
        } else if (tokenOut == address(usdc)) {
            amountIn = (amountOut * 10000) / 9800; // Add 2% slippage
        } else {
            amountIn = (amountOut * 10000) / 9700; // Add 3% slippage
        }
        
        return amountIn;
    }
} 