import { ethers } from "hardhat";
import { writeFileSync, existsSync, mkdirSync } from "fs";
import { join } from "path";

// Hedera Mainnet Configuration
const HEDERA_CONFIG = {
  USDC_ADDRESS: "0x0000000000000000000000000000000000101ae3", // USDC on Hedera
  SAUCERSWAP_ROUTER: "0x00000000000000000000000000000000003c437a", // SaucerSwap Router
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
  console.log("🚀 Starting Hedgera deployment on Hedera mainnet...");
  
  // Get deployer
  const [deployer] = await ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const network = await ethers.provider.getNetwork();
  
  console.log(`📝 Deploying with account: ${deployerAddress}`);
  console.log(`🌐 Network: ${network.name} (Chain ID: ${network.chainId})`);
  console.log(`💰 Account balance: ${ethers.formatEther(await ethers.provider.getBalance(deployerAddress))} HBAR`);
  
  // Verify we're on Hedera mainnet
  if (network.chainId !== 295n) {
    throw new Error(`❌ Wrong network! Expected Hedera mainnet (295), got ${network.chainId}`);
  }

  const addresses: Partial<DeploymentAddresses> = {
    usdc: HEDERA_CONFIG.USDC_ADDRESS,
    saucerSwapRouter: HEDERA_CONFIG.SAUCERSWAP_ROUTER,
    deployer: deployerAddress,
    chainId: Number(network.chainId),
    timestamp: Math.floor(Date.now() / 1000),
  };

  console.log("\n📋 Deployment Configuration:");
  console.log(`   USDC Address: ${addresses.usdc}`);
  console.log(`   SaucerSwap Router: ${addresses.saucerSwapRouter}`);
  console.log(`   Creation Fee: ${ethers.formatUnits(HEDERA_CONFIG.INITIAL_CREATION_FEE, 6)} USDC`);

  // 1. Deploy IndexRegistry
  console.log("\n🏗️  Step 1: Deploying IndexRegistry...");
  const IndexRegistry = await ethers.getContractFactory("IndexRegistry");
  const registry = await IndexRegistry.deploy(deployerAddress, {
    gasLimit: 15000000,
    gasPrice: 350000000000,
  });
  await registry.waitForDeployment();
  addresses.registry = await registry.getAddress();
  console.log(`   ✅ IndexRegistry deployed to: ${addresses.registry}`);

  // 2. Deploy Router
  console.log("\n🏗️  Step 2: Deploying Router...");
  const Router = await ethers.getContractFactory("Router");
  const router = await Router.deploy(
    addresses.usdc!,
    addresses.saucerSwapRouter!,
    deployerAddress,
    {
      gasLimit: 15000000,
      gasPrice: 350000000000,
    }
  );
  await router.waitForDeployment();
  addresses.router = await router.getAddress();
  console.log(`   ✅ Router deployed to: ${addresses.router}`);

  // 3. Deploy IndexFactory
  console.log("\n🏗️  Step 3: Deploying IndexFactory...");
  const IndexFactory = await ethers.getContractFactory("IndexFactory");
  const factory = await IndexFactory.deploy(
    addresses.registry,
    addresses.usdc!,
    deployerAddress,
    {
      gasLimit: 15000000,
      gasPrice: 350000000000,
    }
  );
  await factory.waitForDeployment();
  addresses.factory = await factory.getAddress();
  console.log(`   ✅ IndexFactory deployed to: ${addresses.factory}`);

  // 4. Configure contracts
  console.log("\n⚙️  Step 4: Configuring contracts...");
  
  // Set router in factory
  console.log("   🔗 Setting router in IndexFactory...");
  await factory.setRouter(addresses.router, {
    gasLimit: 15000000,
    gasPrice: 350000000000,
  });
  console.log("   ✅ Router configured in IndexFactory");

  // Add factory as authorized in registry
  console.log("   🔗 Authorizing IndexFactory in IndexRegistry...");
  await registry.addAuthorizedFactory(addresses.factory, {
    gasLimit: 15000000,
    gasPrice: 350000000000,
  });
  console.log("   ✅ IndexFactory authorized in IndexRegistry");

  // Get deployment block
  const currentBlock = await ethers.provider.getBlockNumber();
  addresses.deploymentBlock = currentBlock;

  // 5. Verify deployments
  console.log("\n🔍 Step 5: Verifying deployments...");
  
  // Verify IndexRegistry
  const registryIndexCount = await registry.getIndexCount();
  console.log(`   📊 IndexRegistry: ${registryIndexCount} indexes`);
  
  // Verify Router
  const routerUSDC = await router.getUSDC();
  const routerSaucerSwap = await router.getSaucerSwapRouter();
  console.log(`   🔄 Router USDC: ${routerUSDC}`);
  console.log(`   🔄 Router SaucerSwap: ${routerSaucerSwap}`);
  
  // Verify Factory
  const factoryRouter = await factory.router();
  const factoryCreationFee = await factory.indexCreationFee();
  console.log(`   🏭 Factory router: ${factoryRouter}`);
  console.log(`   🏭 Factory creation fee: ${ethers.formatUnits(factoryCreationFee, 6)} USDC`);

  // 6. Save deployment addresses
  console.log("\n💾 Step 6: Saving deployment addresses...");
  
  const deploymentsDir = join(process.cwd(), "deployments");
  if (!existsSync(deploymentsDir)) {
    mkdirSync(deploymentsDir, { recursive: true });
  }

  const deploymentFile = join(deploymentsDir, "hedera-mainnet.json");
  const fullAddresses: DeploymentAddresses = addresses as DeploymentAddresses;
  
  writeFileSync(deploymentFile, JSON.stringify(fullAddresses, null, 2));
  console.log(`   ✅ Deployment addresses saved to: ${deploymentFile}`);

  // 7. Generate deployment summary
  console.log("\n📊 Deployment Summary:");
  console.log("==================================================");
  console.log(`🌐 Network: Hedera Mainnet (${network.chainId})`);
  console.log(`📦 Deployer: ${deployerAddress}`);
  console.log(`🏗️  Block: ${currentBlock}`);
  console.log(`⏰ Timestamp: ${new Date(addresses.timestamp! * 1000).toISOString()}`);
  console.log("\n📝 Contract Addresses:");
  console.log(`   📊 IndexRegistry: ${addresses.registry}`);
  console.log(`   🔄 Router: ${addresses.router}`);
  console.log(`   🏭 IndexFactory: ${addresses.factory}`);
  console.log("\n🔗 External Addresses:");
  console.log(`   💰 USDC: ${addresses.usdc}`);
  console.log(`   🥞 SaucerSwap: ${addresses.saucerSwapRouter}`);
  
  console.log("\n🎉 Deployment completed successfully!");

  return fullAddresses;
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  }); 