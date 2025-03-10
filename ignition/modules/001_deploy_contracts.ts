import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("BearedMintModule", (m) => {
  const UNISWAP_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  const UNISWAP_FACTORY = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  
  // Ensure we extract the address correctly
  const DEPLOYER_ACCOUNT = m.getAccount(0);
  console.log(DEPLOYER_ACCOUNT)
  const DEPLOYER = process.env.DEPLOYER_ADDRESS || "0x8F3d8E8aa095eb8D5A9AdD053e249955061EB358";

  console.log("🚀 Deploying with the following parameters:");
  console.log(`🛠️ UNISWAP_ROUTER: ${UNISWAP_ROUTER}`);
  console.log(`🏭 UNISWAP_FACTORY: ${UNISWAP_FACTORY}`);
  console.log(`👤 DEPLOYER: ${DEPLOYER}`);

  try {
    const bearedMintFactory = m.contract("BearedMintFactory", [UNISWAP_ROUTER, UNISWAP_FACTORY]);
    const bearedMintLiquidityLock = m.contract("BearedMintLiquidityLock", []);
    const bearedMintTimelock = m.contract("BearedMintTimelock", [DEPLOYER_ACCOUNT, 2 * 24 * 60 * 60]);

    const bearedMintToken = m.contract("BearedMintToken", [
      UNISWAP_ROUTER,
      UNISWAP_FACTORY,
      DEPLOYER,
    ]);

    console.log("✅ Contracts initialized successfully.");

    return {
      bearedMintToken,
      bearedMintFactory,
      bearedMintTimelock,
      bearedMintLiquidityLock,
    };
  } catch (error) {
    console.error("❌ Deployment initialization failed:", error);
    throw error;
  }
});
