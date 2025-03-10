import { ethers } from "hardhat";
import { expect } from "chai";

describe("BearedMintModule - Combined Test Suite", function () {
  let deployer: any, user1: any, user2: any;
  let bearedMintToken: any, bearedMintFactory: any, bearedMintTimelock: any, bearedMintLiquidityLock: any;

  before(async () => {
    [deployer, user1, user2] = await ethers.getSigners();

    const UNISWAP_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    const UNISWAP_FACTORY = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

    const BearedMintFactory = await ethers.getContractFactory("BearedMintFactory");
    const BearedMintLiquidityLock = await ethers.getContractFactory("BearedMintLiquidityLock");
    const BearedMintTimelock = await ethers.getContractFactory("BearedMintTimelock");
    const BearedMintToken = await ethers.getContractFactory("BearedMintToken");

    bearedMintFactory = await BearedMintFactory.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY);
    bearedMintLiquidityLock = await BearedMintLiquidityLock.deploy();
    bearedMintTimelock = await BearedMintTimelock.deploy(deployer.address, 2 * 24 * 60 * 60);
    bearedMintToken = await BearedMintToken.deploy(UNISWAP_ROUTER, UNISWAP_FACTORY, deployer.address);
  });

  describe("Deployment Tests", function () {
    it("Should deploy all contracts correctly", async () => {
      expect(bearedMintFactory.address).to.properAddress;
      expect(bearedMintLiquidityLock.address).to.properAddress;
      expect(bearedMintTimelock.address).to.properAddress;
      expect(bearedMintToken.address).to.properAddress;
    });

    it("Should assign DEFAULT_ADMIN_ROLE to deployer", async () => {
      const adminRole = await bearedMintToken.DEFAULT_ADMIN_ROLE();
      expect(await bearedMintToken.hasRole(adminRole, deployer.address)).to.be.true;
    });
  });

  describe("Token Functional Tests", function () {
    it("Should allow buying tokens", async () => {
      await deployer.sendTransaction({ to: bearedMintToken.address, value: ethers.parseEther("1") });
      const balance = await bearedMintToken.balanceOf(deployer.address);
      expect(balance).to.be.gt(0);
    });

    it("Should allow transferring tokens", async () => {
      const transferAmount = ethers.parseUnits("1000", 18);
      await bearedMintToken.transfer(user1.address, transferAmount);
      expect(await bearedMintToken.balanceOf(user1.address)).to.equal(transferAmount);
    });

    it("Should allow selling tokens", async () => {
      const balance = await bearedMintToken.balanceOf(user1.address);
      await bearedMintToken.connect(user1).sell(balance);
      expect(await bearedMintToken.balanceOf(user1.address)).to.equal(0);
    });

    it("Should revert selling without tokens", async () => {
      await expect(bearedMintToken.connect(user2).sell(1000)).to.be.revertedWith("InsufficientBalance");
    });
  });

  describe("Liquidity Lock Tests", function () {
    it("Should lock and unlock liquidity", async () => {
      const lockAmount = ethers.parseUnits("500", 18);
      await bearedMintToken.transfer(user1.address, lockAmount);
      await bearedMintToken.connect(user1).approve(bearedMintLiquidityLock.address, lockAmount);

      const lockTx = await bearedMintLiquidityLock.connect(user1).lockLiquidity(bearedMintToken.address, lockAmount, 30 * 24 * 60 * 60);
      const receipt = await lockTx.wait();
      const lockId = receipt.events[0].args.lockId;

      await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]);
      await bearedMintLiquidityLock.connect(user1).unlockLiquidity(bearedMintToken.address, lockId);

      expect(await bearedMintToken.balanceOf(user1.address)).to.equal(lockAmount);
    });
  });

  describe("Timelock Functional Tests", function () {
    it("Should queue and execute transaction after delay", async () => {
      const data = bearedMintToken.interface.encodeFunctionData("pause", []);

      const latestBlock = await ethers.provider.getBlock("latest");
      if (!latestBlock) throw new Error("Failed to fetch the latest block");
      const eta = latestBlock.timestamp + 3 * 24 * 60 * 60;
      await bearedMintTimelock.queueTransaction(bearedMintToken.address, 0, "", data, eta);

      await ethers.provider.send("evm_increaseTime", [3 * 24 * 60 * 60]);
      await bearedMintTimelock.executeTransaction(bearedMintToken.address, 0, "", data, eta);

      expect(await bearedMintToken.paused()).to.be.true;
    });

    it("Should prevent executing transaction before delay", async () => {
      const data = bearedMintToken.interface.encodeFunctionData("pause", []);

      const latestBlock = await ethers.provider.getBlock("latest");
      if (!latestBlock) throw new Error("Failed to fetch the latest block");
      const eta = latestBlock.timestamp + 2 * 24 * 60 * 60;
      await bearedMintTimelock.queueTransaction(bearedMintToken.address, 0, "", data, eta);

      await expect(
        bearedMintTimelock.executeTransaction(bearedMintToken.address, 0, "", data, eta)
      ).to.be.revertedWith("Transaction hasn't surpassed delay");
    });
  });

  describe("Factory Deployment Tests", function () {
    it("Should create a new BearedMint token", async () => {
      const tx = await bearedMintFactory.createBearedMint(deployer.address, "TokenX", "TKX");
      const receipt = await tx.wait();
      const newTokenAddress = receipt.events[0].args.tokenAddress;

      expect(await bearedMintFactory.isValidBearedMintToken(newTokenAddress)).to.be.true;
    });
  });
});
