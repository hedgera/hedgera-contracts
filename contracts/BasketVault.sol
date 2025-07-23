// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IBasketVault.sol";
import "./interfaces/IIndexRegistry.sol";
import "./interfaces/IIndexToken.sol";
import "./interfaces/IRouter.sol";
import "./libraries/Types.sol";

/**
 * @title BasketVault
 * @notice Vault contract that handles minting and redeeming of index tokens using USDC
 * @dev Manages basket tokens and handles proportional swapping
 */
contract BasketVault is Ownable, ReentrancyGuard, IBasketVault {
    using SafeERC20 for IERC20;

    /// @notice The index ID this vault manages
    uint256 public immutable indexId;
    
    /// @notice The registry contract
    IIndexRegistry public immutable registry;
    
    /// @notice The index token contract
    IIndexToken public indexToken;
    
    /// @notice The router for DEX operations
    IRouter public router;
    
    /// @notice USDC token contract
    IERC20 public immutable usdc;
    
    /// @notice Collected fees in USDC
    uint256 public collectedFees;
    
    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10000;
    
    /// @notice Minimum mint amount in USDC (to prevent dust)
    uint256 public constant MIN_MINT_AMOUNT = 1e6; // 1 USDC
    
    /// @notice Maximum slippage for swaps (5%)
    uint256 public constant MAX_SLIPPAGE = 500;

    /**
     * @notice Constructor
     * @param indexId_ The index ID this vault manages
     * @param registry_ Address of the registry contract
     * @param usdc_ Address of the USDC token
     * @param owner_ Owner of the vault
     */
    constructor(
        uint256 indexId_,
        address registry_,
        address usdc_,
        address owner_
    ) Ownable(owner_) {
        require(registry_ != address(0), "BasketVault: registry cannot be zero");
        require(usdc_ != address(0), "BasketVault: USDC cannot be zero");
        
        indexId = indexId_;
        registry = IIndexRegistry(registry_);
        usdc = IERC20(usdc_);
    }

    /**
     * @notice Initializes the vault with token and router addresses
     * @param indexToken_ Address of the index token
     * @param router_ Address of the router
     */
    function initialize(address indexToken_, address router_) external onlyOwner {
        require(address(indexToken) == address(0), "BasketVault: already initialized");
        require(indexToken_ != address(0), "BasketVault: token cannot be zero");
        require(router_ != address(0), "BasketVault: router cannot be zero");
        
        indexToken = IIndexToken(indexToken_);
        router = IRouter(router_);
    }

    /**
     * @notice Mints index tokens by depositing USDC
     * @param usdcAmount Amount of USDC to deposit
     * @param minShares Minimum number of shares to receive
     * @param deadline Transaction deadline
     * @return shares Number of index token shares minted
     */
    function mint(uint256 usdcAmount, uint256 minShares, uint256 deadline) 
        external 
        override 
        nonReentrant 
        returns (uint256 shares) 
    {
        require(block.timestamp <= deadline, "BasketVault: expired");
        require(usdcAmount >= MIN_MINT_AMOUNT, "BasketVault: amount too small");
        require(address(indexToken) != address(0), "BasketVault: not initialized");

        // Get index info
        Types.IndexInfo memory indexInfo = registry.getIndex(indexId);
        require(indexInfo.status == Types.IndexStatus.Active, "BasketVault: index not active");

        // Transfer USDC from user
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        // Calculate fees
        uint256 feeAmount = (usdcAmount * indexInfo.fees.mintFee) / BASIS_POINTS;
        uint256 investmentAmount = usdcAmount - feeAmount;
        
        collectedFees += feeAmount;

        // Calculate shares to mint
        uint256 currentSupply = indexToken.totalSupply();
        if (currentSupply == 0) {
            // First mint: 1 USDC = 1e18 shares (18 decimals)
            shares = investmentAmount * 1e12; // Convert from 6 to 18 decimals
        } else {
            uint256 navPerShare = getNavPerShare();
            shares = (investmentAmount * 1e18) / navPerShare;
        }

        require(shares >= minShares, "BasketVault: insufficient shares");

        // Buy basket tokens
        _buyBasketTokens(investmentAmount, indexInfo.components);

        // Mint index tokens
        indexToken.mint(msg.sender, shares);

        // Update registry metrics
        uint256 newTvl = getTotalValueLocked();
        registry.updateIndexMetrics(indexId, newTvl, usdcAmount);

        emit Minted(msg.sender, indexId, usdcAmount, shares, getNavPerShare());
        emit FeesCollected(indexId, feeAmount, 0); // 0 = mint fee

        return shares;
    }

    /**
     * @notice Redeems index tokens for USDC
     * @param shares Number of shares to redeem
     * @param minAmount Minimum USDC amount to receive
     * @param deadline Transaction deadline
     * @return amount Amount of USDC received
     */
    function redeem(uint256 shares, uint256 minAmount, uint256 deadline) 
        external 
        override 
        nonReentrant 
        returns (uint256 amount) 
    {
        require(block.timestamp <= deadline, "BasketVault: expired");
        require(shares > 0, "BasketVault: shares must be positive");
        require(indexToken.balanceOf(msg.sender) >= shares, "BasketVault: insufficient balance");

        // Get index info
        Types.IndexInfo memory indexInfo = registry.getIndex(indexId);

        // Calculate user's share of the vault
        uint256 totalSupply = indexToken.totalSupply();
        require(totalSupply > 0, "BasketVault: no supply");

        // Sell proportional amount of basket tokens
        uint256 grossAmount = _sellBasketTokens(shares, totalSupply, indexInfo.components);

        // Calculate fees
        uint256 feeAmount = (grossAmount * indexInfo.fees.redeemFee) / BASIS_POINTS;
        amount = grossAmount - feeAmount;
        
        collectedFees += feeAmount;

        require(amount >= minAmount, "BasketVault: insufficient amount");

        // Burn index tokens
        indexToken.burn(msg.sender, shares);

        // Transfer USDC to user
        usdc.safeTransfer(msg.sender, amount);

        // Update registry metrics
        uint256 newTvl = getTotalValueLocked();
        registry.updateIndexMetrics(indexId, newTvl, grossAmount);

        emit Redeemed(msg.sender, indexId, shares, amount, getNavPerShare());
        emit FeesCollected(indexId, feeAmount, 1); // 1 = redeem fee

        return amount;
    }

    /**
     * @notice Gets the current NAV per share in USDC
     * @return navPerShare NAV per share (18 decimals)
     */
    function getNavPerShare() public view override returns (uint256 navPerShare) {
        uint256 totalSupply = indexToken.totalSupply();
        if (totalSupply == 0) {
            return 1e18; // 1 USDC per share initially
        }

        uint256 totalValue = getTotalValueLocked();
        return (totalValue * 1e18) / totalSupply;
    }

    /**
     * @notice Gets the total value locked in USDC
     * @return tvl Total value locked (6 decimals)
     */
    function getTotalValueLocked() public view override returns (uint256 tvl) {
        Types.IndexInfo memory indexInfo = registry.getIndex(indexId);
        
        for (uint256 i = 0; i < indexInfo.components.length; i++) {
            address token = indexInfo.components[i].token;
            uint256 balance = IERC20(token).balanceOf(address(this));
            
            if (balance > 0) {
                // Get token value in USDC via router price query
                // For MVP: simplified - assume 1:1 for now, real implementation would use DEX prices
                tvl += balance; // This would need proper price conversion
            }
        }

        return tvl;
    }

    /**
     * @notice Gets the current basket composition
     * @return components Array of current component balances and weights
     */
    function getBasketComposition() external view override returns (Types.Component[] memory components) {
        Types.IndexInfo memory indexInfo = registry.getIndex(indexId);
        components = new Types.Component[](indexInfo.components.length);
        
        for (uint256 i = 0; i < indexInfo.components.length; i++) {
            components[i] = indexInfo.components[i];
            components[i].balance = IERC20(indexInfo.components[i].token).balanceOf(address(this));
        }
        
        return components;
    }

    /**
     * @notice Gets the index ID this vault manages
     * @return The index ID
     */
    function getIndexId() external view override returns (uint256) {
        return indexId;
    }

    /**
     * @notice Updates basket weights (only owner for MVP)
     * @param newWeights Array of new weights in basis points
     */
    function updateBasketWeights(uint256[] memory newWeights) external override onlyOwner {
        // For MVP: This would trigger rebalancing logic
        // Simplified implementation for now
        emit BasketRebalanced(indexId, newWeights);
    }

    /**
     * @notice Withdraws collected fees
     * @param to Address to send fees to
     * @param amount Amount of fees to withdraw in USDC
     */
    function withdrawFees(address to, uint256 amount) external override onlyOwner {
        require(to != address(0), "BasketVault: to cannot be zero");
        require(amount <= collectedFees, "BasketVault: insufficient fees");
        
        collectedFees -= amount;
        usdc.safeTransfer(to, amount);
        
        emit FeesWithdrawn(to, amount);
    }

    /**
     * @notice Gets the amount of fees collected
     * @return fees Amount of fees in USDC
     */
    function getCollectedFees() external view override returns (uint256 fees) {
        return collectedFees;
    }

    /**
     * @notice Internal function to buy basket tokens with USDC
     * @param usdcAmount Amount of USDC to invest
     * @param components Array of basket components
     */
    function _buyBasketTokens(uint256 usdcAmount, Types.Component[] memory components) internal {
        for (uint256 i = 0; i < components.length; i++) {
            uint256 allocation = (usdcAmount * components[i].weight) / BASIS_POINTS;
            
            if (allocation > 0) {
                // For MVP: simplified swap logic
                // Real implementation would use router.swapExactUSDCForTokens
                // For now, we'll just approve and assume perfect swaps
                usdc.approve(address(router), allocation);
                
                address[] memory path = new address[](2);
                path[0] = address(usdc);
                path[1] = components[i].token;
                
                // router.swapExactUSDCForTokens(
                //     allocation,
                //     0, // minAmountOut - would calculate based on slippage
                //     path,
                //     address(this),
                //     block.timestamp + 300
                // );
            }
        }
    }

    /**
     * @notice Internal function to sell basket tokens for USDC
     * @param shares Number of shares being redeemed
     * @param totalSupply Total supply of index tokens
     * @param components Array of basket components
     * @return usdcAmount Amount of USDC received
     */
    function _sellBasketTokens(
        uint256 shares, 
        uint256 totalSupply, 
        Types.Component[] memory components
    ) internal returns (uint256 usdcAmount) {
        for (uint256 i = 0; i < components.length; i++) {
            uint256 tokenBalance = IERC20(components[i].token).balanceOf(address(this));
            uint256 tokensToSell = (tokenBalance * shares) / totalSupply;
            
            if (tokensToSell > 0) {
                // For MVP: simplified swap logic
                IERC20(components[i].token).approve(address(router), tokensToSell);
                
                address[] memory path = new address[](2);
                path[0] = components[i].token;
                path[1] = address(usdc);
                
                // uint256[] memory amounts = router.swapExactTokensForUSDC(
                //     tokensToSell,
                //     0, // minAmountOut
                //     path,
                //     address(this),
                //     block.timestamp + 300
                // );
                // usdcAmount += amounts[amounts.length - 1];
                
                // For MVP: assume 1:1 conversion for simplicity
                usdcAmount += tokensToSell;
            }
        }
        
        return usdcAmount;
    }
} 