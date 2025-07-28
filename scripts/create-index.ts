import { ethers } from "hardhat";
import { readFileSync } from "fs";
import { join } from "path";

// Real token addresses on Hedera
const HEDERA_TOKENS = {
  WBTC: "0x0000000000000000000000000000000000101afb",   // Wrapped Bitcoin
  WETH: "0x000000000000000000000000000000000008437c",   // Wrapped Ethereum  
  WLINK: "0x0000000000000000000000000000000000101b07",  // Wrapped Chainlink
  HBAR: "0x0000000000000000000000000000000000163b5a",   // HBAR (Hedera native)
  SAUCE: "0x00000000000000000000000000000000000b2ad5",  // SaucerSwap token
  BONZO: "0x00000000000000000000000000000000007e545e",  // Bonzo token
  BSL: "0x000000000000000000000000000000000043a076",    // BSL token
  PACK: "0x0000000000000000000000000000000000492a28",   // HashPack token
};

interface IndexConfig {
  name: string;
  symbol: string;
  tokens: string[];
  weights: number[]; // basis points (10000 = 100%)
  mintFee: number;   // basis points
  redeemFee: number; // basis points
  description: string;
}

const HEDERA_INDEXES: IndexConfig[] = [
  {
    name: "Blue Chip Crypto Index",
    symbol: "BCCI",
    tokens: [HEDERA_TOKENS.WBTC, HEDERA_TOKENS.WETH, HEDERA_TOKENS.WLINK, HEDERA_TOKENS.HBAR],
    weights: [3000, 3000, 2000, 2000], // 30% WBTC, 30% WETH, 20% WLINK, 20% HBAR
    mintFee: 50,  // 0.5%
    redeemFee: 50, // 0.5%
    description: "Blue chip cryptocurrencies including BTC, ETH, LINK and HBAR"
  },
  {
    name: "Hedera DeFi Index",
    symbol: "HDI",
    tokens: [HEDERA_TOKENS.HBAR, HEDERA_TOKENS.SAUCE, HEDERA_TOKENS.BONZO, HEDERA_TOKENS.BSL, HEDERA_TOKENS.PACK],
    weights: [4000, 2500, 1500, 1000, 1000], // 40% HBAR, 25% SAUCE, 15% BONZO, 10% BSL, 10% PACK
    mintFee: 75,  // 0.75%
    redeemFee: 75, // 0.75%
    description: "Native Hedera ecosystem tokens and DeFi projects"
  }
];

async function loadDeploymentAddresses() {
  try {
    const deploymentFile = join(process.cwd(), "deployments", "hedera-mainnet.json");
    const deployment = JSON.parse(readFileSync(deploymentFile, "utf8"));
    return deployment;
  } catch (error) {
    throw new Error("❌ Deployment file not found. Please run deployment script first.");
  }
}

async function main() {
  console.log("🏗️  Creating sample indexes on Hedgera...");
  
  // Load deployment addresses
  const deployment = await loadDeploymentAddresses();
  console.log(`📝 Using IndexFactory at: ${deployment.factory}`);
  
  // Get signer
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log(`👤 Creating indexes as: ${deployerAddress}`);
  
  // Connect to contracts
  const IndexFactory = await ethers.getContractFactory("IndexFactory");
  const factory = IndexFactory.attach(deployment.factory);
  
  const IndexRegistry = await ethers.getContractFactory("IndexRegistry");
  const registry = IndexRegistry.attach(deployment.registry);
  
  // Check initial state
  const initialIndexCount = await registry.getIndexCount();
  console.log(`📊 Current index count: ${initialIndexCount}`);
  
  // Check factory configuration
  const creationFee = await factory.indexCreationFee();
  console.log(`💰 Index creation fee: ${ethers.formatUnits(creationFee, 6)} USDC`);
  
  // Create indexes
  const createdIndexes = [];
  
  for (let i = 0; i < HEDERA_INDEXES.length; i++) {
    const config = HEDERA_INDEXES[i];
    console.log(`\n🏗️  Creating Index ${i + 1}: ${config.name} (${config.symbol})`);
    console.log(`   📝 Description: ${config.description}`);
    console.log(`   🏷️  Tokens: ${config.tokens.length}`);
    console.log(`   ⚖️  Weights: ${config.weights.map(w => `${w/100}%`).join(', ')}`);
    console.log(`   💸 Fees: ${config.mintFee/100}% mint, ${config.redeemFee/100}% redeem`);
    
    try {
      // Create the index with fixed gas settings
      const tx = await factory.createIndex(
        config.name,
        config.symbol,
        deployerAddress, // curator = deployer
        config.tokens,
        config.weights,
        config.mintFee,
        config.redeemFee,
        { 
          gasLimit: 15000000,
          gasPrice: 350000000000
        }
      );
      
      console.log(`   📤 Transaction sent: ${tx.hash}`);
      console.log(`   ⏳ Waiting for confirmation...`);
      
      const receipt = await tx.wait();
      console.log(`   ✅ Confirmed in block: ${receipt?.blockNumber}`);
      
      // Parse the IndexCreated event
      const eventFilter = factory.filters.IndexCreated();
      const events = await factory.queryFilter(eventFilter, receipt?.blockNumber, receipt?.blockNumber);
      
      if (events.length > 0) {
        const event = events[events.length - 1]; // Get the latest event
        const indexId = event.args?.indexId;
        const vault = event.args?.vault;
        const indexToken = event.args?.indexToken;
        
        console.log(`   📊 Index ID: ${indexId}`);
        console.log(`   🏦 Vault: ${vault}`);
        console.log(`   🪙 Token: ${indexToken}`);
        
        createdIndexes.push({
          id: Number(indexId),
          name: config.name,
          symbol: config.symbol,
          vault,
          indexToken,
          config
        });
      }
      
    } catch (error) {
      console.error(`   ❌ Failed to create ${config.name}:`, error);
      continue;
    }
    
    // Wait a bit between deployments
    if (i < HEDERA_INDEXES.length - 1) {
      console.log("   ⏱️  Waiting 2 seconds before next deployment...");
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }
  
  // Final verification
  console.log("\n🔍 Verifying created indexes...");
  const finalIndexCount = await registry.getIndexCount();
  console.log(`📊 Final index count: ${finalIndexCount}`);
  
  // List all created indexes
  console.log("\n📋 Created Indexes Summary:");
  console.log("=" * 60);
  
  for (const index of createdIndexes) {
    console.log(`🆔 ID: ${index.id}`);
    console.log(`📛 Name: ${index.name} (${index.symbol})`);
    console.log(`🏦 Vault: ${index.vault}`);
    console.log(`🪙 Token: ${index.indexToken}`);
    console.log(`📊 Tokens: ${index.config.tokens.length}, Fees: ${index.config.mintFee/100}%/${index.config.redeemFee/100}%`);
    console.log("---");
  }
  
  console.log("\n🎉 Index creation completed!");
  console.log(`✅ Successfully created ${createdIndexes.length} out of ${HEDERA_INDEXES.length} indexes`);
  
  if (createdIndexes.length > 0) {
    console.log("\n📋 Next Steps:");
    console.log("   1. Run mint script to buy index tokens");
    console.log("   2. Run redeem script to sell index tokens");
    console.log(`   💡 Try minting from Index ID: ${createdIndexes[0].id}`);
  }
  
  // Save created indexes info
  const indexesFile = join(process.cwd(), "deployments", "created-indexes.json");
  require("fs").writeFileSync(indexesFile, JSON.stringify(createdIndexes, null, 2));
  console.log(`💾 Index details saved to: ${indexesFile}`);
  
  return createdIndexes;
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Index creation failed:", error);
    process.exit(1);
  }); 