import { ethers } from "hardhat";
import { readFileSync } from "fs";

async function main() {
  console.log("💰 Redeeming Index Tokens...");
  
  // Load deployment addresses
  const deployment = JSON.parse(readFileSync("deployments/hedera-mainnet.json", "utf8"));
  const [signer] = await ethers.getSigners();
  
  console.log(`📝 Signer: ${signer.address}`);
  console.log(`📊 Registry: ${deployment.registry}`);
  
  // Get contracts
  const registry = await ethers.getContractAt("IndexRegistry", deployment.registry);
  const usdc = await ethers.getContractAt("IERC20", deployment.usdc);
  
  // Configuration for redeeming
  const REDEEM_CONFIG = {
    indexId: 0,           // TEST index (first index created)
    sharePercentage: 50,  // Redeem 50% of shares
    minUsdcAmount: 0,     // Minimum USDC (0 for testing)
    deadline: Math.floor(Date.now() / 1000) + 1800, // 30 minutes from now
    inKind: false         // Redeem for USDC, not tokens
  };
  
  console.log(`\n🎯 Redeem Configuration:`);
  console.log(`   Index ID: ${REDEEM_CONFIG.indexId}`);
  console.log(`   Share %: ${REDEEM_CONFIG.sharePercentage}%`);
  console.log(`   Min USDC: ${REDEEM_CONFIG.minUsdcAmount} USDC`);
  console.log(`   In-Kind: ${REDEEM_CONFIG.inKind ? "Yes (tokens)" : "No (USDC)"}`);
  console.log(`   Deadline: ${new Date(REDEEM_CONFIG.deadline * 1000).toISOString()}`);
  
  try {
    // Get index info
    console.log(`\n📋 Getting index information...`);
    const indexInfo = await registry.getIndex(REDEEM_CONFIG.indexId);
    console.log(`   Index: ${indexInfo.name} (${indexInfo.symbol})`);
    console.log(`   Vault: ${indexInfo.vault}`);
    console.log(`   Token: ${indexInfo.indexToken}`);
    
    // Get contracts
    const vault = await ethers.getContractAt("BasketVault", indexInfo.vault);
    const indexToken = await ethers.getContractAt("IndexToken", indexInfo.indexToken);
    
    // Check current balances
    console.log(`\n💰 Current Balances:`);
    const usdcBalance = await usdc.balanceOf(signer.address);
    console.log(`   USDC Balance: ${ethers.formatUnits(usdcBalance, 6)} USDC`);
    
    const shareBalance = await indexToken.balanceOf(signer.address);
    console.log(`   Index Shares: ${ethers.formatEther(shareBalance)} ${indexInfo.symbol}`);
    
    if (shareBalance === 0n) {
      console.log(`\n❌ No shares to redeem! Run mint-tokens first.`);
      return;
    }
    
    // Calculate shares to redeem
    const sharesToRedeem = shareBalance * BigInt(REDEEM_CONFIG.sharePercentage) / 100n;
    console.log(`   🔄 Shares to redeem: ${ethers.formatEther(sharesToRedeem)} ${indexInfo.symbol}`);
    
    // Get current share price for estimate
    try {
      const sharePrice = await vault.getNavPerShare();
      const estimatedUsdc = sharesToRedeem * sharePrice / ethers.parseEther("1");
      console.log(`   📊 Current Share Price: ${ethers.formatUnits(sharePrice, 18)} USDC`);
      console.log(`   📈 Estimated USDC: ${ethers.formatUnits(estimatedUsdc, 6)} USDC`);
    } catch (e) {
      console.log(`   📊 Could not get redemption estimate`);
    }
    
    // Check share allowance for vault
    const shareAllowance = await indexToken.allowance(signer.address, indexInfo.vault);
    console.log(`   Vault Share Allowance: ${ethers.formatEther(shareAllowance)} ${indexInfo.symbol}`);
    
    // Approve shares if needed
    if (shareAllowance < sharesToRedeem) {
      console.log(`\n🔓 Approving shares for vault...`);
      const approveTx = await indexToken.approve(indexInfo.vault, sharesToRedeem, {
        gasLimit: 15000000,
        gasPrice: 350000000000
      });
      await approveTx.wait();
      console.log(`   ✅ Shares approved for vault`);
    }
    
    // Execute redeem
    console.log(`\n💸 Redeeming tokens...`);
    const redeemTx = await vault.redeem(
      sharesToRedeem,
      REDEEM_CONFIG.minUsdcAmount,
      REDEEM_CONFIG.deadline,
      {
        gasLimit: 15000000,
        gasPrice: 350000000000
      }
    );
    
    console.log(`   📤 Transaction sent: ${redeemTx.hash}`);
    console.log(`   ⏳ Waiting for confirmation...`);
    
    const receipt = await redeemTx.wait();
    
    if (receipt && receipt.status === 1) {
      console.log(`   ✅ Redeem successful!`);
      console.log(`   🧾 Gas used: ${receipt.gasUsed.toString()}`);
      
      // Check new balances
      console.log(`\n💰 Updated Balances:`);
      const newUsdcBalance = await usdc.balanceOf(signer.address);
      console.log(`   USDC Balance: ${ethers.formatUnits(newUsdcBalance, 6)} USDC`);
      
      const newShareBalance = await indexToken.balanceOf(signer.address);
      console.log(`   Index Shares: ${ethers.formatEther(newShareBalance)} ${indexInfo.symbol}`);
      
      const usdcDiff = newUsdcBalance - usdcBalance;
      const sharesDiff = shareBalance - newShareBalance;
      console.log(`   🎉 Redeemed: ${ethers.formatEther(sharesDiff)} ${indexInfo.symbol} shares`);
      console.log(`   💰 Received: ${ethers.formatUnits(usdcDiff, 6)} USDC`);
      
    } else {
      console.log(`   ❌ Redeem transaction failed`);
    }
    
  } catch (error: any) {
    console.log(`❌ Redemption failed: ${error.message || error}`);
    
    // Additional error details
    if (error.receipt) {
      console.log(`   🧾 Gas used: ${error.receipt.gasUsed}`);
      console.log(`   📊 Status: ${error.receipt.status}`);
    }
  }
  
  console.log("\n🎉 Redeem operation completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Script failed:", error);
    process.exit(1);
  }); 