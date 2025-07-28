import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

const HEDERA_CONFIG = {
  USDC_ADDRESS: "0x000000000000000000000000000000000006f89a", // USDC on Hedera
  SAUCERSWAP_ROUTER: "0x00000000000000000000000000000000002e7a5d", // SaucerSwap V1 Router
  INITIAL_CREATION_FEE: "1000000", // 1 USDC (6 decimals)
};

interface DeploymentAddresses {
  usdc: string;
  saucerSwapRouter: string;
  registry: string;
  router: string;
  factory: string;
  deployer: string;
  deploymentBlock: number;
  timestamp: number;
  chainId: number;
}

async function main() {
  console.log("🚀 Deploying Hedgera contracts to Hedera mainnet...");
  
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const network = await ethers.provider.getNetwork();
  
  console.log("📋 Deployment Details:");
  console.log(`  Network: ${network.name} (${network.chainId})`);
  console.log(`  Deployer: ${deployerAddress}`);
  console.log(`  USDC: ${HEDERA_CONFIG.USDC_ADDRESS}`);
  console.log(`  SaucerSwap Router: ${HEDERA_CONFIG.SAUCERSWAP_ROUTER}`);
  
  const balance = await ethers.provider.getBalance(deployerAddress);
  console.log(`  Balance: ${ethers.formatEther(balance)} HBAR\n`);

  const deploymentOptions = {
    gasLimit: 15000000,
    gasPrice: 350000000000, // 350 gwei
  };

  const addresses: Partial<DeploymentAddresses> = {
    usdc: HEDERA_CONFIG.USDC_ADDRESS,
    saucerSwapRouter: HEDERA_CONFIG.SAUCERSWAP_ROUTER,
    deployer: deployerAddress,
    chainId: Number(network.chainId),
    timestamp: Math.floor(Date.now() / 1000),
  };

  try {
    // 1. Deploy Registry
    console.log("📝 Deploying IndexRegistry...");
    const IndexRegistry = await ethers.getContractFactory("IndexRegistry");
    const registry = await IndexRegistry.deploy(deployerAddress, deploymentOptions);
    await registry.waitForDeployment();
    addresses.registry = await registry.getAddress();
    console.log(`✅ IndexRegistry deployed: ${addresses.registry}`);

    // 2. Deploy Router
    console.log("📝 Deploying Router...");
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(
      addresses.usdc!,
      addresses.saucerSwapRouter!,
      deployerAddress,
      deploymentOptions
    );
    await router.waitForDeployment();
    addresses.router = await router.getAddress();
    console.log(`✅ Router deployed: ${addresses.router}`);

    // 3. Deploy Factory
    console.log("📝 Deploying IndexFactory...");
    const IndexFactory = await ethers.getContractFactory("IndexFactory");
    const factory = await IndexFactory.deploy(
      addresses.registry!,
      addresses.usdc!,
      deployerAddress,
      deploymentOptions
    );
    await factory.waitForDeployment();
    addresses.factory = await factory.getAddress();
    console.log(`✅ IndexFactory deployed: ${addresses.factory}`);

    // Get deployment block
    const deploymentTx = await factory.deploymentTransaction();
    if (deploymentTx) {
      const receipt = await deploymentTx.wait();
      addresses.deploymentBlock = receipt?.blockNumber || 0;
    }

    // 4. Set up initial configuration
    console.log("\n⚙️ Setting up initial configuration...");
    
    // Add factory as authorized in registry
    console.log("🔗 Adding factory as authorized in registry...");
    const addFactoryTx = await registry.addAuthorizedFactory(addresses.factory!, deploymentOptions);
    await addFactoryTx.wait();
    console.log("✅ Factory authorized in registry");

    // Set router in factory
    console.log("🔀 Setting router in factory...");
    const setRouterTx = await factory.setRouter(addresses.router!, deploymentOptions);
    await setRouterTx.wait();
    console.log("✅ Router set in factory");

    // Set initial creation fee to 1 USDC
    console.log("💰 Setting initial creation fee...");
    const setFeeTx = await factory.updateIndexCreationFee(HEDERA_CONFIG.INITIAL_CREATION_FEE, deploymentOptions);
    await setFeeTx.wait();
    console.log("✅ Creation fee set to 1 USDC");

    // Approve USDC for the factory (10 USDC allowance)
    console.log("✅ Approving USDC for factory...");
    const usdc = await ethers.getContractAt("IERC20", HEDERA_CONFIG.USDC_ADDRESS);
    const approveTx = await usdc.approve(addresses.factory!, ethers.parseUnits("10", 6), deploymentOptions);
    await approveTx.wait();
    console.log("✅ USDC approved for factory");

    // 5. Save deployment addresses
    const deploymentsDir = path.join(__dirname, "..", "deployments");
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir);
    }

    const deploymentFile = path.join(deploymentsDir, "hedera-mainnet.json");
    fs.writeFileSync(deploymentFile, JSON.stringify(addresses, null, 2));
    
    console.log("\n📊 Deployment Summary:");
    console.log(`📝 Registry: ${addresses.registry}`);
    console.log(`🔀 Router: ${addresses.router}`);
    console.log(`🏭 Factory: ${addresses.factory}`);
    console.log(`💾 Saved to: ${deploymentFile}`);
    console.log(`📦 Block: ${addresses.deploymentBlock}`);
    
    console.log("\n🎉 Deployment completed successfully!");

  } catch (error) {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 