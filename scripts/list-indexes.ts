import { ethers } from "hardhat";
import { readFileSync } from "fs";

async function main() {
  console.log("📊 Listing All Hedgera Indexes...");
  
  // Load deployment addresses
  const deployment = JSON.parse(readFileSync("deployments/hedera-mainnet.json", "utf8"));
  
  console.log(`📝 Registry: ${deployment.registry}`);
  
  // Get registry contract
  const registry = await ethers.getContractAt("IndexRegistry", deployment.registry);
  
  try {
    // Get total index count
    const indexCount = await registry.getIndexCount();
    console.log(`\n📈 Total Indexes: ${indexCount.toString()}`);
    
    if (indexCount === 0n) {
      console.log("📭 No indexes created yet.");
      return;
    }
    
    console.log("\n📋 Index Details:");
    console.log("=".repeat(80));
    
    // List all indexes
    for (let i = 0; i < indexCount; i++) {
      try {
        console.log(`\n🔢 Index ${i + 1}:`);
        
        // Get index info
        const indexInfo = await registry.getIndex(i);
        console.log(`   📛 Name: ${indexInfo.name}`);
        console.log(`   🏷️  Symbol: ${indexInfo.symbol}`);
        console.log(`   👤 Curator: ${indexInfo.curator}`);
        console.log(`   📅 Created: ${new Date(Number(indexInfo.creationTime) * 1000).toISOString()}`);
        console.log(`   🔗 Index Token: ${indexInfo.indexToken}`);
        console.log(`   🏦 Basket Vault: ${indexInfo.vault}`);
        console.log(`   ✅ Status: ${indexInfo.status} (0=Active, 1=Inactive, 2=Deprecated)`);
        
        // Display basic index info
        console.log(`   💰 TVL: ${ethers.formatUnits(indexInfo.totalValueLocked, 6)} USDC`);
        console.log(`   📊 Volume: ${ethers.formatUnits(indexInfo.totalVolume, 6)} USDC`);
        console.log(`   💸 Mint Fee: ${indexInfo.fees.mintFee / 100}%`);
        console.log(`   💸 Redeem Fee: ${indexInfo.fees.redeemFee / 100}%`);
        console.log(`   🪙 Components: ${indexInfo.components.length} tokens`);
        
      } catch (indexError) {
        console.log(`   ❌ Error loading index ${i + 1}: ${indexError.message}`);
      }
    }
    
    console.log("\n" + "=".repeat(80));
    console.log(`📊 Summary: ${indexCount} total indexes listed`);
    
  } catch (error) {
    console.log(`❌ Failed to list indexes: ${error.message}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Listing failed:", error);
    process.exit(1);
  }); 