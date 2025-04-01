// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "hardhat/console.sol";

/**
 * @title BearedMintToken 
 * @notice Implementation of a bonding curve token with Uniswap migration capability
 * @dev Implements secure token mechanics with bonding curve pricing and migration to Uniswap
 */
contract BearedMintToken is ERC20, ReentrancyGuard, Pausable, AccessControl {
    using Math for uint256;
    using Address for address;

    error NotMigrated();
    error AlreadyMigrated();
    error InvalidAmount();
    error ExceedsPriceImpact();
    error InsufficientBalance();
    error NotAuthorized();
    error InvalidAddress();
    error ExceededRateLimit();
    error ExceedsTotalSupply();
    error NoPendingPayments();
    error MigrationThreshHoldNotMet();
    error TransferFailed();

    // Role definitions 40.000.000.000.000.000.000 - 193.750.000.000.000.000.000 -
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Constants
    uint256 public constant TOTAL_SUPPLY = 31_000_000_000 * 1e18;     // 31B tokens with 18 decimals
    uint256 public constant INITIAL_VIRTUAL_TOKEN_RESERVE = 15_500_000_000 * 1e18;  // 50% of total supply
    uint256 public constant INITIAL_VIRTUAL_ETH_RESERVE = 100 ether;     // 100 CELO initial reserve 
    uint256 public constant MIGRATION_THRESHOLD = 24_800_000_000 * 1e18; // 80% of total supply
    uint256 public constant MIGRATION_FEE = 0.15 ether;               // Fee for migration
    uint256 public constant MIN_PURCHASE = 0.01 ether;                // Minimum purchase amount
    uint256 public constant MAX_PURCHASE = 50 ether;                  // Maximum purchase amount
    uint256 public constant MAX_CONCURRENT_USERS = 100;               // Maximum number of concurrent users
    uint256 public PRICE_IMPACT_LIMIT = 10;                          // 10% max price impact (now mutable)
    mapping(address => uint256) private _pendingWithdrawals;

    // State variables
    uint256 public virtualTokenReserve = INITIAL_VIRTUAL_TOKEN_RESERVE;
    uint256 public virtualEthReserve = INITIAL_VIRTUAL_ETH_RESERVE;
    uint256 public totalCollectedETH;
    uint256 public activeUserCount;                                   // Track number of active users

    bool public migrated;
    bool public emergencyMode;

    uint256 public lastActionTimestamp;
    uint256 public constant RATE_LIMIT_INTERVAL = 300;               // 5 minutes between actions
    uint256 public constant MAX_ACTIONS_IN_INTERVAL = 5;             // Max 5 actions per interval
    mapping(address => uint256) public actionCounter;
    mapping(address => uint256) public lastActionTime;
    mapping(address => bool) public isActiveUser;                     // Track active users

    // Proof of Purpose Tracking
    struct GrowthMetrics {
        uint256 uniqueHolders;
        uint256 totalTransactions;
        uint256 communityEngagementScore;
        uint256 socialImpactScore;
        uint256 lastUpdateTimestamp;
    }

    GrowthMetrics public growthMetrics;
    mapping(address => bool) private _countedHolders;
    mapping(address => uint256) private _lastActivityTimestamp;

    // AI Integration Interface
    address public aiController;
    event AIParametersUpdated(uint256 timestamp, uint256 newPriceImpact, uint256 newBondingCurveFactor);
    event SocialImpactUpdated(uint256 timestamp, uint256 newScore);

    // Events
    event TokensPurchased(address indexed buyer, uint256 ethAmount, uint256 tokenAmount);
    event TokensSold(address indexed seller,uint256 tokenAmount, uint256 ethAmount);
    event MigrationExecuted(uint256 ethAmount, uint256 tokenAmount, address uniswapPair);
    event VirtualReservesUpdated(uint256 virtualTokenReserve, uint256 virtualEthReserve);
    event EmergencyWithdraw(address indexed caller, uint256 ethAmount);
    event WithdrawalQueued(address indexed payee, uint256 amount);
    event Withdrawn(address indexed payee, uint256 amount);

    // Uniswap integration
    IUniswapV2Router02 public immutable uniswapRouter;
    IUniswapV2Factory public immutable uniswapFactory;
    address public uniswapPair;

        // Modifiers
    modifier whenNotMigrated() {
        require(!migrated, "AlreadyMigrated");
        _;
    }

    modifier withinPriceImpact(uint256 priceImpact) {
        require(priceImpact <= PRICE_IMPACT_LIMIT, "ExceedsPriceImpact");
        _;
    }
    
    modifier rateLimit(address user) {
        require(
            block.timestamp - lastActionTime[user] >= RATE_LIMIT_INTERVAL || actionCounter[user] < MAX_ACTIONS_IN_INTERVAL, "ExceededRateLimit"
        );

        if (block.timestamp - lastActionTime[user] >= RATE_LIMIT_INTERVAL) {
            actionCounter[user] = 1;
        } else {
            actionCounter[user] = actionCounter[user] + 1;
        }

        lastActionTime[user] = block.timestamp;
        _;
    }

    /**
     * @notice Contract constructor
     * @param _router Address of Uniswap V2 Router
     * @param _factory Address of Uniswap V2 Factory
     * @param _admin Address of the admin
     */
    constructor(address _router, address _factory, address _admin) ERC20("BearedMint", "BMT") payable { 
        require(_router != address(0), "InvalidAddress");
        require(_factory != address(0), "InvalidAddress");
        require(_admin != address(0), "InvalidAddress");
        require(msg.value >= INITIAL_VIRTUAL_ETH_RESERVE, "Insufficient initial ETH");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        aiController = _admin;
        
        virtualTokenReserve = INITIAL_VIRTUAL_TOKEN_RESERVE; 
        virtualEthReserve = INITIAL_VIRTUAL_ETH_RESERVE;

        uniswapRouter = IUniswapV2Router02(_router);
        uniswapFactory = IUniswapV2Factory(_factory);

        lastActionTimestamp = block.timestamp;
    }

    /**
     * @notice Buy tokens with ETH
     * @dev Implements bonding curve purchase mechanism
     */
    function buy() external payable nonReentrant whenNotPaused whenNotMigrated rateLimit(msg.sender) {
        require(msg.value >= MIN_PURCHASE, "Amount too Low");
        require(msg.value <= MAX_PURCHASE, "Amount exceeds limit");
        require(activeUserCount < MAX_CONCURRENT_USERS || isActiveUser[msg.sender], "Max users reached"); // Todo: remove the cap

        uint256 tokenAmount = calculatePurchaseReturn(msg.value);
        require(tokenAmount > 0, "InvalidAmount");
        
        // Calculate max allowed purchase based on reserve and active users
        uint256 maxAllowedPurchase = virtualTokenReserve / (activeUserCount + 1);
        require(tokenAmount <= maxAllowedPurchase, "Purchase exceeds allowed limit");
 
        // Ensure enough tokens are available with buffer
        uint256 reserveBuffer = virtualTokenReserve / 20; // 5% buffer
        require(virtualTokenReserve >= tokenAmount + reserveBuffer, "Not enough tokens in reserve");
        require(totalSupply() + tokenAmount <= TOTAL_SUPPLY, "Amount exceeds totalsupply");
        
        // Calculate price impact
        uint256 priceImpact = calculatePriceImpact(msg.value, virtualEthReserve);
        require(priceImpact <= PRICE_IMPACT_LIMIT, "Amount exceeds price Impact");

        // Update reserves
        virtualEthReserve = virtualEthReserve + msg.value;
        virtualTokenReserve = virtualTokenReserve - tokenAmount;
        totalCollectedETH = totalCollectedETH + msg.value;

        // Update user tracking
        if (!isActiveUser[msg.sender]) {
            isActiveUser[msg.sender] = true;
            activeUserCount++;
        }

        bool shouldMigrate = totalSupply() + tokenAmount >= MIGRATION_THRESHOLD;

        _mint(msg.sender, tokenAmount);
        _updateGrowthMetrics(msg.sender);

        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
        emit VirtualReservesUpdated(virtualTokenReserve, virtualEthReserve);

        if (shouldMigrate) {
            migrateToUniswap();
        }
    }

    /**
     * @notice Sell tokens back to the contract
     * @param tokenAmount Amount of tokens to sell
     */
    function sell(uint256 tokenAmount) external nonReentrant whenNotPaused whenNotMigrated rateLimit(msg.sender) {
        require(tokenAmount > 0, "InvalidAmount");
        require(balanceOf(msg.sender) >= tokenAmount, "InsufficientBalance");
        uint256 ethAmount = calculateSaleReturn(tokenAmount);
        require(ethAmount > 0, "InvalidAmount");
        require(virtualEthReserve >= ethAmount, "Insufficient virtual ETH reserve");
        require(address(this).balance >= ethAmount, "Insufficient contract balance");
        
        _burn(msg.sender, tokenAmount);
        virtualTokenReserve += tokenAmount; // ToDo: check if this is correct
        virtualEthReserve -= ethAmount;  // Deduct from virtual reserve

        _queueWithdrawal(msg.sender, ethAmount);
        _updateGrowthMetrics(msg.sender);
        
        emit TokensSold(msg.sender, tokenAmount, ethAmount);
        emit VirtualReservesUpdated(virtualTokenReserve, virtualEthReserve);
    }

    function _queueWithdrawal(address payee, uint256 amount) private {
        if (payee == address(0)) {revert InvalidAddress();}
        _pendingWithdrawals[payee] = _pendingWithdrawals[payee] + amount;
        emit WithdrawalQueued(payee, amount);
    }

    function withdrawPendingPayments() external nonReentrant {
        uint256 amount = _pendingWithdrawals[msg.sender];
        if (amount == 0) {revert NoPendingPayments();}
        if (address(this).balance < amount) {revert ("Insufficient contract balance");} // Todo: check if this is correct

        _pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {revert TransferFailed();}

        emit Withdrawn(msg.sender, amount);
    }

    function pendingWithdrawals(address payee) external view returns (uint256) {
        return _pendingWithdrawals[payee];
    }


    /**
    * @notice Calculate the number of tokens to mint based on ETH sent
     * @param ethAmount The amount of ETH sent for purchasing tokens
     * @return The number of tokens to mint
     */
    function calculatePurchaseReturn(uint256 ethAmount) public view returns (uint256) {
        require(ethAmount > 0, "ETH amount must be greater than zero");
        require(virtualTokenReserve > 0, "Insufficient token reserve");

        // Simplified bonding curve calculation
        uint256 baseTokenAmount = (ethAmount * virtualTokenReserve) / virtualEthReserve; // 50 max 
        
        // Apply growth-based adjustments and user count scaling
        uint256 growthMultiplier = 100 + (growthMetrics.communityEngagementScore / 10);
        uint256 userScaling = activeUserCount >= 50 ? 0 : 100 - (activeUserCount * 2); // Reduce token amount as more users participate
        uint256 tokenAmount = (baseTokenAmount * growthMultiplier * userScaling) / 10000;
        
        // Ensure minimum token amount
        uint256 minTokenAmount = ethAmount * 100; // At least 100 tokens per ETH
        if (tokenAmount < minTokenAmount) {
            tokenAmount = minTokenAmount;
        }
        
        require(tokenAmount > 0, "Token purchase amount too low");
        require(tokenAmount < virtualTokenReserve, "Not enough tokens in reserve");
        return tokenAmount;
    }

   /**
    * @notice Calculate the ETH amount returned when selling tokens
    * @param tokenAmount The amount of tokens to sell
    * @return The ETH amount to be returned
    */
   function calculateSaleReturn(uint256 tokenAmount) public view returns (uint256) {
        require(tokenAmount > 0, "InvalidAmount");
        require(virtualTokenReserve > 0, "Insufficient token reserve");
        
        // Simplified sale calculation
        uint256 ethAmount = (tokenAmount * virtualEthReserve) / virtualTokenReserve;
        
        // Ensure minimum ETH return - minimum: 0.01 ETH per 100 tokens
        uint256 minEthAmount = (tokenAmount * 1e16) / 100; // At least 0.01 ETH per 100 tokens  // (tokenAmount * 10e18) / (100 * 10e18);
        if (ethAmount < minEthAmount || ethAmount == 0) {
            ethAmount = minEthAmount;
        }

        // Cap at available eth reserve
        if (ethAmount > virtualEthReserve) {
            ethAmount = virtualEthReserve;
        }
       
        return ethAmount;
    }


    
    /**
     * @notice Calculate price impact of a trade
     * @param tradeSize Size of the trade in ETH
     * @param currentReserve Current ETH reserve
     * @return Price impact percentage
     */
    function calculatePriceImpact(uint256 tradeSize, uint256 currentReserve) public pure returns (uint256) {
        return tradeSize * (100 / currentReserve);
    }
    
    /**
    * @notice Computes log2(x) using binary search and fixed-point arithmetic.
    * @dev Uses a scaled fixed-point representation (1e18 precision).
    * @param x The input value
    * @return log2Scaled The logarithm of x base 2, scaled by 1e18
    */
    function logBase2(uint256 x) internal pure returns (uint256) {
        require(x > 0, "logBase2: Undefined for zero");
        
        uint256 result = 0;
        uint256 factor = 1e18; // Fixed-point scaling factor
        uint256 y = x;
        
        // Binary search for the integer part
        while (y >= 2) {
            y >>= 1;  // Equivalent to dividing by 2
            result += factor;
        }
        
        // Newton-Raphson for fractional part (for higher precision)
        uint256 z = (x * factor) / (1 << (result / factor)); // Normalize input
        for (uint256 i = 0; i < 5; i++) { // Iterate to refine accuracy
          z = (z * z) / factor;
          if (z >= 2 * factor) {
            z /= 2;
            result += factor / (2**(i + 1));
        }
    }
    
    return result;
    }


    /**
     * @notice Migrate remaining tokens and ETH to Uniswap
     * @dev Can only be called once when migration threshold is met
     */
    function migrateToUniswap() internal {
        require(!migrated, "AlreadyMigrated()");
        require(totalSupply() >= MIGRATION_THRESHOLD, "MigrationThreshHoldNotMet()");
        require(virtualTokenReserve > 0, "Zero token reserve");

        migrated = true;

        uint256 ethForPool = address(this).balance - MIGRATION_FEE;

        // Safely calculate current price with scaling factor to prevent precision loss
        uint256 SCALE = 1e18;
        uint256 currentPrice = (virtualEthReserve * SCALE) / virtualTokenReserve;
        require(currentPrice > 0, "Invalid price");

        // Calculate tokens to migrate with proper scaling
        uint256 tokensToMigrate = (ethForPool * SCALE) / currentPrice;
        require(tokensToMigrate > 0, "Invalid migration amount");

        uint256 tokensToBurn = TOTAL_SUPPLY - totalSupply() - tokensToMigrate;

        // Mint and burn tokens before external calls
        _mint(address(this), tokensToMigrate);
        _burn(address(this), tokensToBurn);

        // Approve before external calls
        _approve(address(this), address(uniswapRouter), tokensToMigrate);

        // Cache token amount to verify after external call
        uint256 preCallTokenBalance = IERC20(address(this)).balanceOf(address(this));

        try
        uniswapRouter.addLiquidityETH{value: ethForPool}(address(this), tokensToMigrate, tokensToMigrate, ethForPool, msg.sender, block.timestamp)
        returns (uint256 tokenAmount, uint256 ethAmount, uint256) {
            require(IERC20(address(this)).balanceOf(address(this)) <= preCallTokenBalance, "Token balance manipulated");  // Verify state wasn't manipulated during external call

            address pair = uniswapFactory.getPair(address(this), uniswapRouter.WETH());
            uniswapPair = pair;
            emit MigrationExecuted(ethAmount, tokenAmount, pair);
        } catch {
            revert("Migration failed");
        }
    }

    /**
     * @notice Emergency withdrawal in case of critical issues
     * @dev Only callable by admin in emergency mode
     */
    function emergencyWithdraw() external nonReentrant onlyRole(ADMIN_ROLE) {
        require(emergencyMode, "Emergency mode not active");

        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        // Update state first
        uint256 amountToWithdraw = balance;
        totalCollectedETH = totalCollectedETH - amountToWithdraw;

        // External call last
        (bool success, ) = msg.sender.call{value: amountToWithdraw}("");
        require(success, "TransferFailed");

        emit EmergencyWithdraw(msg.sender, amountToWithdraw);
    }

    /**
     * @notice Set emergency mode
     * @param _emergencyMode New emergency mode state
     */
    function setEmergencyMode(bool _emergencyMode) external onlyRole(ADMIN_ROLE) {
        emergencyMode = _emergencyMode;
        if (_emergencyMode) {
            _pause();
        } else {
            _unpause();
        }
    }
    
    /**
     * @notice Withdraw accumulated fees post-migration
     * @dev Only callable by admin after migration
    */
    function withdrawFees() external nonReentrant onlyRole(ADMIN_ROLE) {
        require(migrated, "NotMigrated");
        require(address(this).balance >= MIGRATION_FEE, "InsufficientBalance");

        (bool success, ) = msg.sender.call{value: MIGRATION_FEE}("");
        require(success, "TransferFailed");
    }

    function _update(address from, address to, uint256 amount ) internal virtual override whenNotPaused {
        super._update(from, to, amount);
    }

    /**
     * @notice Update growth metrics
     * @dev Called after each transaction
     */
    function _updateGrowthMetrics(address user) internal {
        if (!_countedHolders[user]) {
            growthMetrics.uniqueHolders++;
            _countedHolders[user] = true;
        }
        
        growthMetrics.totalTransactions++;
        
        // Update community engagement score based on activity
        uint256 timeSinceLastActivity = block.timestamp - _lastActivityTimestamp[user];
        if (timeSinceLastActivity < 1 days) {
            growthMetrics.communityEngagementScore += 10;
        }
        
        _lastActivityTimestamp[user] = block.timestamp;
        growthMetrics.lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Update AI parameters
     * @dev Can only be called by AI controller
     */
    function updateAIParameters(uint256 newPriceImpact, uint256 newBondingCurveFactor) external {
        require(msg.sender == aiController, "Not AI controller");
        require(newPriceImpact <= 20, "Price impact too high"); // Max 20% price impact
        PRICE_IMPACT_LIMIT = newPriceImpact;
        emit AIParametersUpdated(block.timestamp, newPriceImpact, newBondingCurveFactor);
    }

    /**
     * @notice Update social impact score
     * @dev Can only be called by admin
     */
    function updateSocialImpactScore(uint256 newScore) external onlyRole(ADMIN_ROLE) {
        require(newScore <= 100, "Score too high");
        growthMetrics.socialImpactScore = newScore;
        emit SocialImpactUpdated(block.timestamp, newScore);
    }

    /**
     * @notice Get current growth metrics
     */
    function getGrowthMetrics() external view returns (
        uint256 uniqueHolders,
        uint256 totalTransactions,
        uint256 communityEngagementScore,
        uint256 socialImpactScore,
        uint256 lastUpdateTimestamp
    ) {
        return (
            growthMetrics.uniqueHolders,
            growthMetrics.totalTransactions,
            growthMetrics.communityEngagementScore,
            growthMetrics.socialImpactScore,
            growthMetrics.lastUpdateTimestamp
        );
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
    receive() external payable {} // if (msg.sender == address(uniswapRouter)) {revert ("Only router can send ETH");}
}
