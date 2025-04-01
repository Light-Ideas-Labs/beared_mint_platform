import { ethers, network } from "hardhat";
import { expect } from "chai";

describe("BearedMintModule - Combined Test Suite", function () {
  let deployer: any, user1: any, user2: any, aiController: any;
  let bearedMintToken: any, bearedMintFactory: any, bearedMintTimelock: any, bearedMintLiquidityLock: any;

  const UNISWAP_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  const UNISWAP_FACTORY = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";

  before(async () => {
    [deployer, user1, user2, aiController] = await ethers.getSigners();
    console.log("balance of user1", await ethers.provider.getBalance(user1.address));

    const BearedMintFactory = await ethers.getContractFactory("BearedMintFactory");
    const BearedMintLiquidityLock = await ethers.getContractFactory("BearedMintLiquidityLock");
    const BearedMintTimelock = await ethers.getContractFactory("BearedMintTimelock");
    const BearedMintToken = await ethers.getContractFactory("BearedMintToken");

    bearedMintFactory = await BearedMintFactory.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY);
    await bearedMintFactory.waitForDeployment();
    
    bearedMintLiquidityLock = await BearedMintLiquidityLock.deploy();
    await bearedMintLiquidityLock.waitForDeployment();
    
    bearedMintTimelock = await BearedMintTimelock.deploy(deployer.address, 2 * 24 * 60 * 60);
    await bearedMintTimelock.waitForDeployment();
  });

  describe("Deployment Tests", function () {
    beforeEach(async () => {
      const BearedMintToken = await ethers.getContractFactory("BearedMintToken");
      bearedMintToken = await BearedMintToken.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address, { value: ethers.parseEther("100") });
      await bearedMintToken.waitForDeployment();
    });

    it("Should deploy all contracts correctly", async () => {
      expect(await bearedMintFactory.getAddress()).to.properAddress;
      expect(await bearedMintLiquidityLock.getAddress()).to.properAddress;
      expect(await bearedMintTimelock.getAddress()).to.properAddress;
      expect(await bearedMintToken.getAddress()).to.properAddress;
    });

    it("Should initialize with correct reserves", async () => {
      const tokenReserve = await bearedMintToken.virtualTokenReserve();
      const ethReserve = await bearedMintToken.virtualEthReserve();
      expect(tokenReserve).to.equal(ethers.parseEther("15500000000")); // 15.5B tokens
      expect(ethReserve).to.equal(ethers.parseEther("100")); // 100 CELO
    });

    it("Should assign DEFAULT_ADMIN_ROLE to deployer", async () => {
      const adminRole = await bearedMintToken.DEFAULT_ADMIN_ROLE();
      expect(await bearedMintToken.hasRole(adminRole, deployer.address)).to.be.true;
    });
  });

  describe("Token Functional Tests", function () {
    beforeEach(async () => {
      const BearedMintToken = await ethers.getContractFactory("BearedMintToken");
      bearedMintToken = await BearedMintToken.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address, { value: ethers.parseEther("100") });
      await bearedMintToken.waitForDeployment();
    });

    it("Should allow buying tokens within limits", async () => {
      console.log("\n=== Testing Token Purchase ===");
      const buyAmount = ethers.parseEther("0.1"); // 0.1 ETH
      console.log(`Buying tokens with ${ethers.formatEther(buyAmount)} ETH`);
      
      await bearedMintToken.connect(deployer).buy({ value: buyAmount });
      const balance = await bearedMintToken.balanceOf(deployer.address);
      console.log(`Received ${ethers.formatEther(balance)} tokens`);
      expect(balance).to.be.gt(0);
    });

    it("Should enforce minimum purchase amount", async () => {
      console.log("\n=== Testing Minimum Purchase ===");
      const minAmount = ethers.parseEther("0.009"); // Below minimum
      console.log(`Attempting to buy with ${ethers.formatEther(minAmount)} ETH (below minimum)`);
      
      await expect(
        bearedMintToken.connect(user1).buy({ value: minAmount })
      ).to.be.revertedWith("Amount too Low");
      console.log("Test passed: Minimum purchase amount enforced");
    });

    it("Should enforce maximum purchase amount", async () => {
      console.log("\n=== Testing Maximum Purchase ===");
      const maxAmount = ethers.parseEther("51"); // Above maximum
      console.log(`Attempting to buy with ${ethers.formatEther(maxAmount)} ETH (above maximum)`);
      
      await expect(
        bearedMintToken.connect(user1).buy({ value: maxAmount })
      ).to.be.revertedWith("Amount exceeds limit");
      console.log("Test passed: Maximum purchase amount enforced");
    });

    it("Should allow transferring tokens", async () => {
      console.log("\n=== Testing Token Transfer ===");
      // First buy some tokens
      const buyAmount = ethers.parseEther("0.1");
      console.log(`Buying initial tokens with ${ethers.formatEther(buyAmount)} ETH`);
      
      await bearedMintToken.connect(deployer).buy({ value: buyAmount });
      const initialBalance = await bearedMintToken.balanceOf(deployer.address);
      console.log(`Initial balance: ${ethers.formatEther(initialBalance)} tokens`);
      
      // Convert to BigInt for division
      const transferAmount = initialBalance / BigInt(2);
      console.log(`Transferring ${ethers.formatEther(transferAmount)} tokens to user1`);
      
      await bearedMintToken.transfer(user1.address, transferAmount);
      
      const user1Balance = await bearedMintToken.balanceOf(user1.address);
      const deployerBalance = await bearedMintToken.balanceOf(deployer.address);
      console.log(`User1 new balance: ${ethers.formatEther(user1Balance)} tokens`);
      console.log(`Deployer new balance: ${ethers.formatEther(deployerBalance)} tokens`);
      
      expect(user1Balance).to.equal(transferAmount);
      expect(deployerBalance).to.equal(initialBalance - transferAmount);
    });
    
    it("Should allow selling tokens", async () => {
      console.log("\n=== Testing Token Sale ===");
      const buyAmount = ethers.parseEther("0.1");
      console.log(`Buying tokens with ${ethers.formatEther(buyAmount)} ETH`);
      await bearedMintToken.connect(user1).buy({ value: buyAmount });
      
      const balance = await bearedMintToken.balanceOf(user1.address);
      console.log(`Initial token balance: ${ethers.formatEther(balance)} tokens`);
      expect(balance).to.be.gt(0, "User1 should have received tokens");
      
      const sellAmount = balance / BigInt(2);
      console.log(`Selling ${ethers.formatEther(sellAmount)} tokens`);
      
      const contractBalanceBefore = await bearedMintToken.getBalance();
      console.log(`Contract balance before: ${ethers.formatEther(contractBalanceBefore)} ETH`);
      
      const virtualEthReserveBefore = await bearedMintToken.virtualEthReserve();
      console.log(`Virtual ETH reserve before: ${ethers.formatEther(virtualEthReserveBefore)} ETH`);
      
      const initialEthBalance = await ethers.provider.getBalance(user1.address);
      console.log(`Initial ETH balance: ${ethers.formatEther(initialEthBalance)} ETH`);

      // approve the token
      const approveTx = await bearedMintToken.connect(user1).approve(await bearedMintToken.getAddress(), sellAmount);
      console.log("approved...");
      const receipt = await approveTx.wait();
      console.log("receipt", receipt);

      // call eth amount form calculateSaleReturn  // 77500000000000000000,000 == 77.5 eth
      const ethAmount = await bearedMintToken.calculateSaleReturn(sellAmount);
      console.log("ethAmount====>", ethAmount);

      // call eth vitual reserve
      const ethVirtualReserve = await bearedMintToken.virtualEthReserve();
      console.log("ethVirtualReserve====>", ethVirtualReserve);
      
      // sell the tokens
      await bearedMintToken.connect(user1).sell(sellAmount);
      
      const newBalance = await bearedMintToken.balanceOf(user1.address);
      console.log(`New token balance: ${ethers.formatEther(newBalance)} tokens`);
      expect(newBalance).to.equal(balance - sellAmount);
      
      const pending = await bearedMintToken.pendingWithdrawals(user1.address);
      console.log(`Pending ETH withdrawals: ${ethers.formatEther(pending)} ETH`);
      expect(pending).to.be.gt(0);
      
      await bearedMintToken.connect(user1).withdrawPendingPayments();
      const finalEthBalance = await ethers.provider.getBalance(user1.address);
      console.log(`ETH balance increased by: ${ethers.formatEther(finalEthBalance - initialEthBalance)} ETH`);
      expect(finalEthBalance).to.be.gt(initialEthBalance);
    });
  });

  describe("User Limit Tests", function () {
    beforeEach(async () => {
      const BearedMintToken = await ethers.getContractFactory("BearedMintToken");
      bearedMintToken = await BearedMintToken.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address, { value: ethers.parseEther("100") });
      await bearedMintToken.waitForDeployment();
    });

    it("Should track active users correctly", async () => {
      // First user
      await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("0.1") });
      expect(await bearedMintToken.isActiveUser(user1.address)).to.be.true;
      expect(await bearedMintToken.activeUserCount()).to.equal(1);

      // Second user
      await bearedMintToken.connect(user2).buy({ value: ethers.parseEther("0.1") });
      expect(await bearedMintToken.isActiveUser(user2.address)).to.be.true;
      expect(await bearedMintToken.activeUserCount()).to.equal(2);
    });

    it("Should allow existing active users to buy even at max users", async () => {
      // Simulate max users reached
      for (let i = 0; i < 99; i++) { // 99 + user1 = 100
        const newUser = ethers.Wallet.createRandom().connect(ethers.provider);
        await deployer.sendTransaction({ to: newUser.address, value: ethers.parseEther("1") });
        await bearedMintToken.connect(newUser).buy({ value: ethers.parseEther("0.1") });
      }

      // Existing active user should still be able to buy
      await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("0.1") });
      expect(await bearedMintToken.balanceOf(user1.address)).to.be.gt(0);
    });
  });

  describe("Reserve Buffer Tests", function () {
    beforeEach(async () => {
      const BearedMintToken = await ethers.getContractFactory("BearedMintToken");
      bearedMintToken = await BearedMintToken.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address, { value: ethers.parseEther("100") });
      await bearedMintToken.waitForDeployment();
    });

    // Buy tokens to reduce reserve
    it("Should maintain reserve buffer", async () => {
      const buyAmount = ethers.parseEther("0.1");
      for (let i = 0; i < 6; i++) { //Exceed 5 actions
        if(i > 0) {
          await ethers.provider.send("evm_increaseTime", [300]);  // 5 minutes
          await network.provider.send("evm_mine"); // Mine a block
        }
        await bearedMintToken.connect(deployer).buy({ value: buyAmount });
      }
      const reserve = await bearedMintToken.virtualTokenReserve();
      console.log("<====reserve====>", reserve);
      expect(reserve).to.be.gt(ethers.parseEther("14725000000"));  // 95% of initial reserve
    });
  });

  describe("Rate Limit Tests", function () {
    beforeEach(async () => {
      const BearedMintToken = await ethers.getContractFactory("BearedMintToken");
      bearedMintToken = await BearedMintToken.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address, { value: ethers.parseEther("100") });
      await bearedMintToken.waitForDeployment();
    });

    it("Should enforce rate limits", async () => {
      for (let i = 0; i < 5; i++) {
        await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("0.1") });
      }
      await expect(bearedMintToken.connect(user1).buy({ value: ethers.parseEther("0.1") })).to.be.revertedWith("ExceededRateLimit");
    });

    it("Should allow buys after rate limit period", async () => {
      // First buy
      await bearedMintToken.connect(user2).buy({ value: ethers.parseEther("0.1") });
      
      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [301]); // 5 minutes + 1 second
      
      // Should be able to buy again
      await bearedMintToken.connect(user2).buy({ value: ethers.parseEther("0.1") });
      expect(await bearedMintToken.balanceOf(user2.address)).to.be.gt(0);
    });
  });

  describe("Proof of Purpose Tests", function () {
    beforeEach(async () => {
      const BearedMintTokenFactory = await ethers.getContractFactory("BearedMintToken");
      bearedMintToken = await BearedMintTokenFactory.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address, { value: ethers.parseEther("100") });
      await bearedMintToken.waitForDeployment();
    });

    it("Should track unique holders correctly", async () => {
      await bearedMintToken.connect(deployer).buy({ value: ethers.parseEther("0.1") });
      const initialMetrics = await bearedMintToken.getGrowthMetrics();
      expect(initialMetrics.uniqueHolders).to.equal(1);
  
      await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("0.1") });
      const metricsAfter = await bearedMintToken.getGrowthMetrics();
      expect(metricsAfter.uniqueHolders).to.equal(2);
    });

    it("Should track transaction volume", async () => {
      const initialMetrics = await bearedMintToken.getGrowthMetrics();
      const initialTransactions = BigInt(initialMetrics.totalTransactions);
      await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("0.1") });
      await bearedMintToken.connect(user2).buy({ value: ethers.parseEther("0.1") });
      const finalMetrics = await bearedMintToken.getGrowthMetrics();
      expect(finalMetrics.totalTransactions).to.equal(initialTransactions + BigInt(2));
    });

    it("Should update community engagement score", async () => {
      const initialMetrics = await bearedMintToken.getGrowthMetrics();
      const initialScore = initialMetrics.communityEngagementScore;
      await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("0.1") });
      await ethers.provider.send("evm_increaseTime", [12 * 60 * 60]);
      await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("0.1") });
      const finalMetrics = await bearedMintToken.getGrowthMetrics();
      expect(finalMetrics.communityEngagementScore).to.be.gt(initialScore);
    });

    it("Should allow admin to update social impact score", async () => {
      const newScore = 75;
      await bearedMintToken.updateSocialImpactScore(newScore);
      const metrics = await bearedMintToken.getGrowthMetrics();
      expect(metrics.socialImpactScore).to.equal(newScore);
    });

    it("Should revert non-admin social impact score update", async () => {
      await expect(
        bearedMintToken.connect(user1).updateSocialImpactScore(50)
      ).to.be.reverted;
    });
  });

  describe("AI-Driven Features Tests", function () {
    beforeEach(async () => {
      const BearedMintTokenFactory = await ethers.getContractFactory("BearedMintToken");
      bearedMintToken = await BearedMintTokenFactory.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address, { value: ethers.parseEther("100") });
      await bearedMintToken.waitForDeployment();
      await bearedMintToken.grantRole(await bearedMintToken.OPERATOR_ROLE(), aiController.address);
    });
  
    it("Should allow AI controller to update parameters", async () => {
      await bearedMintToken.connect(deployer).updateAIParameters(15, 1);
      expect(await bearedMintToken.PRICE_IMPACT_LIMIT()).to.equal(15);
    });
  });

  describe("Liquidity Lock Tests", function () {
    beforeEach(async () => {
      const BearedMintLiquidityLock = await ethers.getContractFactory("BearedMintLiquidityLock");
      bearedMintLiquidityLock = await BearedMintLiquidityLock.deploy();
      await bearedMintLiquidityLock.waitForDeployment();
    });

    it("Should lock and unlock liquidity", async () => {
      await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("1") });
      const lockAmount = await bearedMintToken.balanceOf(user1.address);
      await bearedMintToken.connect(user1).approve(await bearedMintLiquidityLock.getAddress(), lockAmount);
      const lockTx = await bearedMintLiquidityLock.connect(user1).lockLiquidity(
        await bearedMintToken.getAddress(), lockAmount, 30 * 24 * 60 * 60
      );
      const receipt = await lockTx.wait();
      const lockEvent = receipt.logs.find((log: any) => log.fragment?.name === "LiquidityLocked");
      const lockId = lockEvent.args.lockId;
      await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]);
      await bearedMintLiquidityLock.connect(user1).unlockLiquidity(await bearedMintToken.getAddress(), lockId);
      expect(await bearedMintToken.balanceOf(user1.address)).to.equal(lockAmount);
    });
  
    it("Should prevent early unlocking", async () => {
      await bearedMintToken.connect(user1).buy({ value: ethers.parseEther("1") });
      const lockAmount = await bearedMintToken.balanceOf(user1.address);
      await bearedMintToken.connect(user1).approve(await bearedMintLiquidityLock.getAddress(), lockAmount);
      const lockTx = await bearedMintLiquidityLock.connect(user1).lockLiquidity(
        await bearedMintToken.getAddress(), lockAmount, 30 * 24 * 60 * 60
      );
      const receipt = await lockTx.wait();
      const lockEvent = receipt.logs.find((log: any) => log.fragment?.name === "LiquidityLocked");
      const lockId = lockEvent.args.lockId;
      await expect(bearedMintLiquidityLock.connect(user1).unlockLiquidity(await bearedMintToken.getAddress(), lockId)).to.be.revertedWith("Still locked");
    });
  });

  describe("Timelock Functional Tests", function () {
    beforeEach(async () => {
      const BearedMintTokenFactory = await ethers.getContractFactory("BearedMintToken");
      const BearedMintTimelockFactory = await ethers.getContractFactory("BearedMintTimelock");
      bearedMintToken = await BearedMintTokenFactory.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address, { value: ethers.parseEther("100") });
      await bearedMintToken.waitForDeployment();
      console.log("BearedMintToken deployed at:", await bearedMintToken.getAddress());
  
      bearedMintTimelock = await BearedMintTimelockFactory.deploy(deployer.address, 2 * 24 * 60 * 60);
      await bearedMintTimelock.waitForDeployment();
      console.log("BearedMintTimelock deployed at:", await bearedMintTimelock.getAddress());
  
      const timelockAddress = await bearedMintTimelock.getAddress();
      if (!timelockAddress) {
          throw new Error("Timelock address is null or undefined");
      }
  
      await bearedMintTimelock.grantRole(await bearedMintTimelock.DEFAULT_ADMIN_ROLE(), deployer.address);
      await bearedMintToken.grantRole(await bearedMintToken.ADMIN_ROLE(), timelockAddress);

      console.log("max delay====>", await bearedMintTimelock.MAXIMUM_DELAY());
      console.log("min delay====>", await bearedMintTimelock.MINIMUM_DELAY());
      console.log("grace period====>", await bearedMintTimelock.GRACE_PERIOD());
    });

    it("Should queue and execute transaction after delay", async () => {
      console.log("setting emergency mode...");
      const data = bearedMintToken.interface.encodeFunctionData("setEmergencyMode", [true]);
      const latestBlock = await ethers.provider.getBlock("latest");
      if (!latestBlock) throw new Error("Failed to fetch the latest block");
      const eta = latestBlock.timestamp + 3 * 24 * 60 * 60;
      await bearedMintTimelock.queueTransaction(await bearedMintToken.getAddress(), 0, "", data, eta);
      await ethers.provider.send("evm_increaseTime", [3 * 24 * 60 * 60]);
      await bearedMintTimelock.executeTransaction(await bearedMintToken.getAddress(), 0, "", data, eta);
      expect(await bearedMintToken.emergencyMode()).to.be.true;
    });

    it("Should prevent executing transaction before delay", async () => {
      console.log("setting emergency mode...");
      const data = bearedMintToken.interface.encodeFunctionData("setEmergencyMode", [true]);
      console.log("data====>", data);
      const latestBlock = await ethers.provider.getBlock("latest");
      console.log("latestBlock====>", latestBlock);
      if (!latestBlock) throw new Error("Failed to fetch the latest block");
      const eta = latestBlock.timestamp + 2 * 24 * 60 * 60; // 2 days delay
      console.log("eta====>", eta);
      const tx = await bearedMintTimelock.connect(deployer).queueTransaction(await bearedMintToken.getAddress(), 0, "", data, eta);
      console.log("queued...", tx);
      // No time increase
      const receipt = await expect(
        bearedMintTimelock.connect(deployer).executeTransaction(await bearedMintToken.getAddress(), 0, "", data, eta)
      ).to.be.revertedWith("Transaction hasn't surpassed delay");
      console.log("receipt====>", receipt);
    });
  });

  it("Should create a new BearedMint token", async () => {
    const tx = await bearedMintFactory.createBearedMint(deployer.address, "TokenX", "TKX", { value: ethers.parseEther("100") });
    const receipt = await tx.wait();
    const event = receipt.logs.find((log: any) => log.eventName === "BearedMintDeployed");
    expect(event).to.not.be.undefined;
    const newTokenAddress = event.args.tokenAddress;
    expect(await bearedMintFactory.isValidBearedMintToken(newTokenAddress)).to.be.true;
  });
});
