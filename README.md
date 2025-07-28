# Hedgera - Decentralized Index Protocol on Hedera

Hedgera is a decentralized index protocol that allows users to create, mint, and redeem crypto index tokens on the Hedera network. The protocol integrates with SaucerSwap V1 for automated token swapping and uses USDC as the base currency.

## 🏗️ Architecture Overview

Hedgera consists of five core smart contracts that work together to provide a seamless index token experience:

### Core Contracts

- **IndexRegistry** - Central registry managing all index metadata and lifecycle
- **IndexFactory** - Factory contract for creating new index tokens and vaults
- **BasketVault** - Vault contract handling minting/redeeming with automatic token swapping
- **IndexToken** - ERC-20 index token representing ownership of the underlying basket
- **Router** - DEX integration layer for SaucerSwap V1 token swapping

### External Integrations

- **SaucerSwap V1** - Decentralized exchange for token swapping (Uniswap V2 style)
- **USDC** - Base currency for all index operations
- **Hedera Token Service (HTS)** - Native token standard on Hedera

## 🔄 System Flow

### Index Creation Flow
1. User calls `IndexFactory.createIndex()` with token basket configuration
2. Factory deploys new `BasketVault` and `IndexToken` contracts
3. Factory registers the index in `IndexRegistry`
4. Index is ready for minting/redeeming

### Minting Flow
1. User calls `BasketVault.mint()` with USDC amount
2. Vault approves `Router` to spend USDC
3. Router swaps USDC for basket tokens via SaucerSwap V1
4. Vault mints proportional index tokens to user

### Redeeming Flow
1. User calls `BasketVault.redeem()` with index token amount
2. Vault calculates proportional token amounts to sell
3. Vault approves `Router` to spend basket tokens
4. Router swaps basket tokens for USDC via SaucerSwap V1
5. Vault burns index tokens and sends USDC to user

## 🚀 Getting Started

### Prerequisites

- Node.js v18+ (v21.7.3 currently used)
- npm or yarn
- Hedera testnet/mainnet account with HBAR balance
- USDC balance for index operations

### Installation

```bash
# Clone the repository
git clone https://github.com/hedgera/hedgera-contracts
cd hedgera-contracts

# Install dependencies
npm install

# Set up environment
cp .env.example .env
# Add your PRIVATE_KEY to .env
```

### Environment Setup

Create a `.env` file with:
```
PRIVATE_KEY=your_private_key_here
```

### Compilation

```bash
npm run compile
```

### Deployment

Deploy to Hedera mainnet:
```bash
npm run deploy
```

This will deploy all contracts and configure them with:
- USDC address: `0x000000000000000000000000000000000006f89a`
- SaucerSwap V1 Router: `0x00000000000000000000000000000000002e7a5d`
- Creation fee: 1 USDC
- Initial USDC allowance: 10 USDC

## 📝 Usage Examples

### Create an Index

```bash
npm run create-indexes
```

This creates two sample indexes:
- **Blue Chip Crypto Index (BCCI)**: BTC, ETH, LINK, HBAR
- **Hedera DeFi Index (HDI)**: HBAR + Hedera ecosystem tokens

### Mint Index Tokens

```bash
npx hardhat run scripts/mint-tokens.ts --network hedera
```

### Redeem Index Tokens

```bash
npx hardhat run scripts/redeem-tokens.ts --network hedera
```

### List All Indexes

```bash
npx hardhat run scripts/list-indexes.ts --network hedera
```

### Check USDC Balance & Allowance

```bash
npx hardhat run scripts/check-usdc.ts --network hedera
```

## 🏛️ Contract Specifications

### IndexRegistry

Central registry storing all index metadata:

```solidity
struct IndexInfo {
    string name;
    string symbol;
    address curator;
    Component[] components;
    uint256 mintFee;
    uint256 redeemFee;
    IndexStatus status;
    uint256 creationTime;
    address vault;
    address indexToken;
}
```

### IndexFactory

Factory for creating new indexes with validation:

- **Creation Fee**: 1 USDC (configurable)
- **Token Limits**: 2-10 tokens per index
- **Weight Limits**: 1%-50% per token
- **Fee Limits**: Max 5% total fees

### BasketVault

Core vault managing minting and redeeming:

- **Minimum Mint**: 1 USDC
- **Fee Collection**: Separate mint/redeem fees
- **Slippage Protection**: Configurable slippage tolerance
- **Emergency Functions**: Pause/unpause, fee withdrawal

### Router

DEX integration for SaucerSwap V1:

- **Swap Functions**: `swapExactUSDCForTokens`, `swapExactTokensForUSDC`
- **Quote Functions**: `getAmountsOut`, `getAmountsIn`, `getTokenValueInUSDC`
- **Fallback Strategy**: Graceful handling of illiquid pairs
- **Gas Optimization**: Batch swapping for efficiency

## 🔧 Configuration

### Network Configuration

Contracts are configured for Hedera mainnet:
- **Chain ID**: 295 (0x127)
- **RPC URL**: https://mainnet.hashio.io/api
- **Currency**: HBAR
- **Gas Limit**: 15M (for large contracts)
- **Gas Price**: 350 gwei

### Token Addresses

Key token addresses on Hedera mainnet:
- **USDC**: `0x000000000000000000000000000000000006f89a`
- **WBTC**: `0x0000000000000000000000000000000000101afb`
- **WETH**: `0x000000000000000000000000000000000008437c`
- **WLINK**: `0x0000000000000000000000000000000000101b07`
- **HBAR**: `0x0000000000000000000000000000000000163b5a`

## 🛠️ Development

### Debugging

View deployment addresses:
```bash
cat deployments/hedera-mainnet.json
```


## Flow 

sequenceDiagram
    participant User
    participant BasketVault
    participant Router
    participant SaucerSwap
    participant USDC
    participant TokenA
    participant TokenB
    participant IndexToken
    
    Note over User,IndexToken: Minting Process (USDC → Index Tokens)
    
    User->>+BasketVault: mint(100 USDC)
    BasketVault->>USDC: transferFrom(User, Vault, 100 USDC)
    
    Note over BasketVault,SaucerSwap: Swap USDC for Basket Tokens
    
    BasketVault->>USDC: approve(Router, 100 USDC)
    BasketVault->>+Router: swapExactUSDCForTokens(tokens[], amounts[])
    
    Router->>USDC: transferFrom(Vault, Router, 30 USDC)
    Router->>+SaucerSwap: swapExactTokensForTokens(USDC→TokenA)
    SaucerSwap-->>-Router: return TokenA
    Router->>TokenA: transfer(Vault, TokenA)
    
    Router->>USDC: transferFrom(Vault, Router, 70 USDC)
    Router->>+SaucerSwap: swapExactTokensForTokens(USDC→TokenB)
    SaucerSwap-->>-Router: return TokenB
    Router->>TokenB: transfer(Vault, TokenB)
    
    Router-->>-BasketVault: return amounts[]
    
    Note over BasketVault,IndexToken: Mint Index Tokens
    
    BasketVault->>+IndexToken: mint(User, shares)
    IndexToken-->>-User: transfer index tokens
    BasketVault-->>-User: emit Minted event