// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/ISaucerSwapRouter.sol";
import "./libraries/Types.sol";

/**
 * @title Router
 * @notice DEX router for SaucerSwap V1 integration
 * @dev Handles token swaps and price queries for index operations
 */
contract Router is IRouter, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public usdc;
    ISaucerSwapRouter public saucerSwapRouter;

    uint256 public constant DEFAULT_SLIPPAGE = 300; // 3% in basis points
    uint256 public constant MAX_SLIPPAGE = 1000; // 10% max slippage

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);

    constructor(
        address usdc_,
        address saucerSwapRouter_,
        address owner_
    ) Ownable(owner_) {
        require(usdc_ != address(0), "Router: USDC cannot be zero");
        require(saucerSwapRouter_ != address(0), "Router: SaucerSwap router cannot be zero");
        
        usdc = IERC20(usdc_);
        saucerSwapRouter = ISaucerSwapRouter(saucerSwapRouter_);
    }

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
    ) external override nonReentrant returns (uint256[] memory amounts) {
        require(tokens.length == allocations.length, "Router: Length mismatch");
        require(tokens.length == minAmounts.length, "Router: Length mismatch");
        require(totalUSDC > 0, "Router: Invalid amount");

        // Verify total allocation
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocation += allocations[i];
        }
        require(totalAllocation == totalUSDC, "Router: Allocation mismatch");

        // Transfer USDC from sender
        usdc.safeTransferFrom(msg.sender, address(this), totalUSDC);

        amounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 allocation = allocations[i];
            
            if (allocation == 0) {
                amounts[i] = 0;
                continue;
            }

            // Skip swap if token is USDC itself
            if (tokens[i] == address(usdc)) {
                usdc.safeTransfer(recipient, allocation);
                amounts[i] = allocation;
                continue;
            }

            // Approve SaucerSwap router
            usdc.approve(address(saucerSwapRouter), allocation);
            
            // Create swap path: USDC -> Token
            address[] memory path = new address[](2);
            path[0] = address(usdc);
            path[1] = tokens[i];
            
            try saucerSwapRouter.swapExactTokensForTokens(
                allocation,
                minAmounts[i],
                path,
                recipient,
                block.timestamp + 300 // 5 minute deadline
            ) returns (uint256[] memory swapAmounts) {
                amounts[i] = swapAmounts[1]; // Output amount
                
                emit SwapExecuted(
                    address(usdc),
                    tokens[i],
                    allocation,
                    amounts[i],
                    recipient
                );
            } catch {
                // Fallback: Send USDC to recipient if swap fails (for MVP)
                usdc.safeTransfer(recipient, allocation);
                amounts[i] = 0;
            }
        }

        return amounts;
    }

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
    ) external override nonReentrant returns (uint256[] memory usdcAmounts) {
        require(tokens.length == amounts.length, "Router: Length mismatch");
        require(tokens.length == minUSDCAmounts.length, "Router: Length mismatch");

        usdcAmounts = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] == 0) {
                usdcAmounts[i] = 0;
                continue;
            }

            // Skip swap if token is USDC itself
            if (tokens[i] == address(usdc)) {
                IERC20(tokens[i]).safeTransferFrom(msg.sender, recipient, amounts[i]);
                usdcAmounts[i] = amounts[i];
                continue;
            }

            // Transfer token from sender
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
            
            // Approve SaucerSwap router
            IERC20(tokens[i]).approve(address(saucerSwapRouter), amounts[i]);
            
            // Create swap path: Token -> USDC
            address[] memory path = new address[](2);
            path[0] = tokens[i];
            path[1] = address(usdc);
            
            try saucerSwapRouter.swapExactTokensForTokens(
                amounts[i],
                minUSDCAmounts[i],
                path,
                recipient,
                block.timestamp + 300 // 5 minute deadline
            ) returns (uint256[] memory swapAmounts) {
                usdcAmounts[i] = swapAmounts[1]; // Output amount
                
                emit SwapExecuted(
                    tokens[i],
                    address(usdc),
                    amounts[i],
                    usdcAmounts[i],
                    recipient
                );
            } catch {
                // Fallback: Keep tokens if swap fails (for MVP)
                IERC20(tokens[i]).safeTransfer(msg.sender, amounts[i]);
                usdcAmounts[i] = 0;
            }
        }

        return usdcAmounts;
    }

    /**
     * @notice Get output amounts for given input amount and path
     * @param amountIn Input amount
     * @param path Token swap path
     * @return amounts Output amounts
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        try saucerSwapRouter.getAmountsOut(amountIn, path) returns (uint256[] memory result) {
            return result;
        } catch {
            // Fallback: Return 1:1 ratio for MVP
            amounts = new uint256[](path.length);
            amounts[0] = amountIn;
            for (uint256 i = 1; i < path.length; i++) {
                amounts[i] = amountIn; // 1:1 fallback
            }
            return amounts;
        }
    }

    /**
     * @notice Get input amounts for given output amount and path
     * @param amountOut Output amount
     * @param path Token swap path
     * @return amounts Input amounts
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        try saucerSwapRouter.getAmountsIn(amountOut, path) returns (uint256[] memory result) {
            return result;
        } catch {
            // Fallback: Return 1:1 ratio for MVP
            amounts = new uint256[](path.length);
            amounts[path.length - 1] = amountOut;
            for (uint256 i = 0; i < path.length - 1; i++) {
                amounts[i] = amountOut; // 1:1 fallback
            }
            return amounts;
        }
    }

    /**
     * @notice Get token value in USDC
     * @param token Token address
     * @param amount Token amount
     * @return usdcValue Value in USDC
     */
    function getTokenValueInUSDC(address token, uint256 amount) 
        external 
        view 
        override 
        returns (uint256 usdcValue) 
    {
        if (token == address(usdc)) {
            return amount;
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(usdc);

        try saucerSwapRouter.getAmountsOut(amount, path) returns (uint256[] memory amounts) {
            return amounts[1];
        } catch {
            // Fallback: Return input amount for MVP
            return amount;
        }
    }

    /**
     * @notice Update SaucerSwap router address
     * @param newRouter New router address
     */
    function updateSaucerSwapRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0), "Router: Invalid router");
        saucerSwapRouter = ISaucerSwapRouter(newRouter);
    }

    /**
     * @notice Get SaucerSwap router address
     * @return router Router address
     */
    function getSaucerSwapRouter() external view returns (address) {
        return address(saucerSwapRouter);
    }

    /**
     * @notice Emergency token rescue
     * @param token Token address
     * @param amount Amount to rescue
     */
    function rescueToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
} 