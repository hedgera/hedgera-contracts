import { ethers } from "hardhat";
import { readFileSync } from "fs";

async function main() {
  console.log("🪙 Minting Index Tokens...");
  
  // Load deployment addresses
  const deployment = JSON.parse(readFileSync("deployments/hedera-mainnet.json", "utf8"));
  const [signer] = await ethers.getSigners();
  
  console.log(`📝 Signer: ${signer.address}`);
  console.log(`📊 Registry: ${deployment.registry}`);
  
  // Get contracts
  const registry = await ethers.getContractAt("IndexRegistry", deployment.registry);
  const usdc = await ethers.getContractAt("IERC20", deployment.usdc);
  
  // Configuration for minting
  const MINT_CONFIG = {
    indexId: 0,           // TEST index (first index created)
    usdcAmount: ethers.parseUnits("5", 6), // 2 USDC to mint with
    minShares: 0,         // Minimum shares (0 for testing)
    deadline: Math.floor(Date.now() / 1000) + 1800 // 30 minutes from now
  };
  
  console.log(`\n🎯 Mint Configuration:`);
  console.log(`   Index ID: ${MINT_CONFIG.indexId}`);
  console.log(`   USDC Amount: ${ethers.formatUnits(MINT_CONFIG.usdcAmount, 6)} USDC`);
  console.log(`   Min Shares: ${MINT_CONFIG.minShares}`);
  console.log(`   Deadline: ${new Date(MINT_CONFIG.deadline * 1000).toISOString()}`);
  
  try {
    // Get index info
    console.log(`\n📋 Getting index information...`);
    const indexInfo = await registry.getIndex(MINT_CONFIG.indexId);
    console.log(`   Index: ${indexInfo.name} (${indexInfo.symbol})`);
    console.log(`   Vault: ${indexInfo.vault}`);
    console.log(`   Token: ${indexInfo.indexToken}`);
    
    // Get vault contract
    const vault = await ethers.getContractAt("BasketVault", indexInfo.vault);
    
    // Check current balances
    console.log(`\n💰 Current Balances:`);
    const usdcBalance = await usdc.balanceOf(signer.address);
    console.log(`   USDC Balance: ${ethers.formatUnits(usdcBalance, 6)} USDC`);
    
    const indexToken = await ethers.getContractAt("IndexToken", indexInfo.indexToken);
    const shareBalance = await indexToken.balanceOf(signer.address);
    console.log(`   Index Shares: ${ethers.formatEther(shareBalance)} ${indexInfo.symbol}`);
    
    // Check USDC allowance for vault
    const allowance = await usdc.allowance(signer.address, indexInfo.vault);
    console.log(`   Vault Allowance: ${ethers.formatUnits(allowance, 6)} USDC`);
    
    // Approve USDC if needed
    if (allowance < MINT_CONFIG.usdcAmount) {
      console.log(`\n🔓 Approving USDC for vault...`);
      const approveTx = await usdc.approve(indexInfo.vault, MINT_CONFIG.usdcAmount, {
        gasLimit: 15000000,
        gasPrice: 350000000000
      });
      await approveTx.wait();
      console.log(`   ✅ USDC approved for vault`);
    }
    
    // Get current share price for estimate
    try {
      const sharePrice = await vault.getNavPerShare();
      // Convert USDC amount (6 decimals) to shares (18 decimals) 
      const usdcAmount18 = ethers.parseUnits(ethers.formatUnits(MINT_CONFIG.usdcAmount, 6), 18);
      const estimatedShares = (usdcAmount18 * ethers.parseEther("1")) / sharePrice;
      console.log(`   📊 Current Share Price: ${ethers.formatUnits(sharePrice, 18)} USDC`);
      console.log(`   📈 Estimated Shares: ${ethers.formatEther(estimatedShares)} ${indexInfo.symbol}`);
    } catch (e) {
      console.log(`   📊 Could not get share price estimate`);
    }
    
    // Execute mint
    console.log(`\n🏗️  Minting tokens...`);
    const mintTx = await vault.mint(
      MINT_CONFIG.usdcAmount,
      MINT_CONFIG.minShares,
      MINT_CONFIG.deadline,
      {
        gasLimit: 15000000,
        gasPrice: 350000000000
      }
    );
    
    console.log(`   📤 Transaction sent: ${mintTx.hash}`);
    console.log(`   ⏳ Waiting for confirmation...`);
    
    const receipt = await mintTx.wait();
    
    if (receipt && receipt.status === 1) {
      console.log(`   ✅ Mint successful!`);
      console.log(`   🧾 Gas used: ${receipt.gasUsed.toString()}`);
      
      // Check new balances
      console.log(`\n💰 Updated Balances:`);
      const newUsdcBalance = await usdc.balanceOf(signer.address);
      console.log(`   USDC Balance: ${ethers.formatUnits(newUsdcBalance, 6)} USDC`);
      
      const newShareBalance = await indexToken.balanceOf(signer.address);
      console.log(`   Index Shares: ${ethers.formatEther(newShareBalance)} ${indexInfo.symbol}`);
      
      const sharesDiff = newShareBalance - shareBalance;
      console.log(`   🎉 Minted: ${ethers.formatEther(sharesDiff)} ${indexInfo.symbol} shares`);
      
    } else {
      console.log(`   ❌ Mint transaction failed`);
    }
    
  } catch (error) {
    console.log(`❌ Minting failed: ${error.message}`);
    
    // Additional error details
    if (error.receipt) {
      console.log(`   🧾 Gas used: ${error.receipt.gasUsed}`);
      console.log(`   📊 Status: ${error.receipt.status}`);
    }
  }
  
  console.log("\n🎉 Mint operation completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Script failed:", error);
    process.exit(1);
  }); 