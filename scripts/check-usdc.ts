import { ethers } from "hardhat";
import { readFileSync } from "fs";

async function main() {
  console.log("💰 Checking USDC Status...");
  
  // Load deployment addresses
  const deployment = JSON.parse(readFileSync("deployments/hedera-mainnet.json", "utf8"));
  const [signer] = await ethers.getSigners();
  
  console.log(`📝 Signer: ${signer.address}`);
  console.log(`💰 USDC: ${deployment.usdc}`);
  console.log(`🏭 Factory: ${deployment.factory}`);
  
  // Get USDC contract
  const usdc = await ethers.getContractAt("IERC20", deployment.usdc);
  const factory = await ethers.getContractAt("IndexFactory", deployment.factory);
  
  try {
    // Check USDC balance
    const balance = await usdc.balanceOf(signer.address);
    console.log(`\n💰 USDC Balance: ${ethers.formatUnits(balance, 6)} USDC`);
    
    // Check factory allowance
    const allowance = await usdc.allowance(signer.address, deployment.factory);
    console.log(`🏭 Factory Allowance: ${ethers.formatUnits(allowance, 6)} USDC`);
    
    // Check creation fee
    const creationFee = await factory.indexCreationFee();
    console.log(`💸 Creation Fee: ${ethers.formatUnits(creationFee, 6)} USDC`);
    
    // Check if we need approval
    if (balance >= creationFee && allowance < creationFee) {
      console.log(`\n⚠️  Need to approve USDC for factory!`);
      console.log(`   Balance: ${ethers.formatUnits(balance, 6)} USDC ✅`);
      console.log(`   Required: ${ethers.formatUnits(creationFee, 6)} USDC`);
      console.log(`   Allowance: ${ethers.formatUnits(allowance, 6)} USDC ❌`);
      
      console.log(`\n🔧 Approving USDC...`);
      const approveTx = await usdc.approve(deployment.factory, ethers.parseUnits("10", 6), {
        gasLimit: 15000000,
        gasPrice: 350000000000
      });
      await approveTx.wait();
      console.log(`✅ USDC approved for 10 USDC`);
      
    } else if (balance < creationFee) {
      console.log(`\n❌ Insufficient USDC balance!`);
      console.log(`   Need: ${ethers.formatUnits(creationFee, 6)} USDC`);
      console.log(`   Have: ${ethers.formatUnits(balance, 6)} USDC`);
      
    } else {
      console.log(`\n✅ USDC setup looks good!`);
    }
    
  } catch (error) {
    console.log(`❌ Error checking USDC: ${error.message}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Check failed:", error);
    process.exit(1);
  }); 