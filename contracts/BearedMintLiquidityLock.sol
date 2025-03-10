// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BearedMintLiquidityLock
 * @notice Contract to lock Uniswap LP tokens after migration
 */
contract BearedMintLiquidityLock is AccessControl {

    struct LockInfo {
        uint256 amount;
        uint256 unlockTime;
        bool isUnlocked;
        address owner;
        uint256 lockId;
    }

    mapping(address => mapping(uint256 => LockInfo)) public lockInfo;
    mapping(address => uint256) public tokenLockCount;

    event LiquidityLocked(address indexed token, uint256 indexed lockId, address indexed owner, uint256 amount, uint256 unlockTime);
    event LiquidityUnlocked(address indexed token, uint256 indexed lockId, address indexed owner, uint256 amount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function lockLiquidity(address token, uint256 amount, uint256 duration) external returns (uint256 lockId) {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Invalid amount");
        require(duration >= 30 days, "Min 30 days lock");

        lockId = tokenLockCount[token]++;
        uint256 unlockTime = block.timestamp + duration;

        lockInfo[token][lockId] = LockInfo({
            amount: amount,
            unlockTime: unlockTime,
            isUnlocked: false,
            owner: msg.sender,
            lockId: lockId
        });

        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Transfer failed");

        emit LiquidityLocked(token, lockId, msg.sender, amount, unlockTime);
        return lockId;
    }

    function unlockLiquidity(address token, uint256 lockId) external {
        LockInfo storage lock = lockInfo[token][lockId];
        require(lock.amount > 0, "Lock does not exist");
        require(!lock.isUnlocked, "Already unlocked");
        require(block.timestamp >= lock.unlockTime, "Still locked");
        require(msg.sender == lock.owner, "Not the lock owner");

        uint256 amountToTransfer = lock.amount;
        address recipient = lock.owner;

        lock.isUnlocked = true;
        lock.amount = 0;
        require(IERC20(token).transfer(recipient, amountToTransfer), "Transfer failed");

        emit LiquidityUnlocked(token, lockId, recipient, amountToTransfer);
    }
}