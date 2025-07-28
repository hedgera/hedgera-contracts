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
        _buyBasketTokens(investmentAmount);

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
        uint256 grossAmount = _sellBasketTokens(shares);

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
    function getNavPerShare() public override returns (uint256 navPerShare) {
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
    function getTotalValueLocked() public override returns (uint256 tvl) {
        Types.IndexInfo memory indexInfo = registry.getIndex(indexId);
        
        for (uint256 i = 0; i < indexInfo.components.length; i++) {
            address token = indexInfo.components[i].token;
            uint256 balance = IERC20(token).balanceOf(address(this));
            
            if (balance > 0) {
                // Get token value in USDC via router price query
                try router.getTokenValueInUSDC(token, balance) returns (uint256 usdcValue) {
                    tvl += usdcValue;
                } catch {
                    // If pricing fails, skip this token for TVL calculation
                    // In production, might want alternative pricing sources
                }
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
     * @notice Buy basket tokens with USDC
     * @param usdcAmount Amount of USDC to spend
     */
    function _buyBasketTokens(uint256 usdcAmount) internal {
        if (usdcAmount == 0) return;
        
        // Get index info from registry
        Types.IndexInfo memory indexInfo = registry.getIndex(indexId);
        
        // Get token allocations based on weights
        uint256[] memory allocations = new uint256[](indexInfo.components.length);
        address[] memory tokens = new address[](indexInfo.components.length);
        uint256[] memory minAmounts = new uint256[](indexInfo.components.length);
        
        for (uint256 i = 0; i < indexInfo.components.length; i++) {
            allocations[i] = (usdcAmount * indexInfo.components[i].weight) / BASIS_POINTS;
            tokens[i] = indexInfo.components[i].token;
            minAmounts[i] = 0; // Accept any amount for MVP
        }
        
        // Approve Router to spend USDC from this vault
        usdc.approve(address(router), usdcAmount);
        
        // Execute batch swap through Router
        try router.swapExactUSDCForTokens(
            usdcAmount,
            tokens,
            allocations,
            minAmounts,
            address(this)
        ) {
            // Swaps completed successfully
        } catch {
            // If swaps fail, we still have USDC in the vault
            // For MVP: continue operation
        }
    }

    /**
     * @notice Sell basket tokens for USDC
     * @param shareAmount Amount of shares being redeemed
     */
    function _sellBasketTokens(uint256 shareAmount) internal returns (uint256 usdcReceived) {
        uint256 totalShares = indexToken.totalSupply();
        if (totalShares == 0) return 0;
        
        // Get index info from registry
        Types.IndexInfo memory indexInfo = registry.getIndex(indexId);
        
        address[] memory tokens = new address[](indexInfo.components.length);
        uint256[] memory amounts = new uint256[](indexInfo.components.length);
        uint256[] memory minUSDCAmounts = new uint256[](indexInfo.components.length);
        uint256 tokenCount = 0;
        
        // Calculate token amounts to sell based on share proportion
        for (uint256 i = 0; i < indexInfo.components.length; i++) {
            IERC20 token = IERC20(indexInfo.components[i].token);
            uint256 tokenBalance = token.balanceOf(address(this));
            
            if (tokenBalance > 0) {
                uint256 tokenAmount = (tokenBalance * shareAmount) / totalShares;
                if (tokenAmount > 0) {
                    tokens[tokenCount] = indexInfo.components[i].token;
                    amounts[tokenCount] = tokenAmount;
                    minUSDCAmounts[tokenCount] = 0; // Accept any amount for MVP
                    tokenCount++;
                }
            }
        }
        
        if (tokenCount > 0) {
            // Resize arrays to actual token count
            address[] memory tokensToSell = new address[](tokenCount);
            uint256[] memory amountsToSell = new uint256[](tokenCount);
            uint256[] memory minAmounts = new uint256[](tokenCount);
            
            for (uint256 i = 0; i < tokenCount; i++) {
                tokensToSell[i] = tokens[i];
                amountsToSell[i] = amounts[i];
                minAmounts[i] = minUSDCAmounts[i];
                
                // Approve Router to spend each token
                IERC20(tokensToSell[i]).approve(address(router), amountsToSell[i]);
            }
            
            // Execute batch sell through Router
            try router.swapExactTokensForUSDC(
                tokensToSell,
                amountsToSell,
                minAmounts,
                address(this)
            ) returns (uint256[] memory usdcAmounts) {
                // Sum up USDC received
                for (uint256 i = 0; i < usdcAmounts.length; i++) {
                    usdcReceived += usdcAmounts[i];
                }
            } catch {
                // If swaps fail, no USDC received from swaps
                // Tokens remain in vault
                usdcReceived = 0;
            }
        }
        
        return usdcReceived;
    }
} 