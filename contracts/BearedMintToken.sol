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

    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Constants
    uint256 public constant TOTAL_SUPPLY = 31_000_000_000 * 1e18;     // 31B tokens with 18 decimals
    uint256 public constant INITIAL_VIRTUAL_TOKEN_RESERVE = 1.06e27;  // 1.06 * 10^27
    uint256 public constant INITIAL_VIRTUAL_ETH_RESERVE = 1.6e18;     // 1.6 CELO // 100 Celo
    uint256 public constant MIGRATION_THRESHOLD = 799_538_871 * 1e18; // ~80% of total supply
    uint256 public constant MIGRATION_FEE = 0.15 ether;               // Fee for migration
    uint256 public constant MIN_PURCHASE = 0.01 ether;                // Minimum purchase amount
    uint256 public constant MAX_PURCHASE = 50 ether;                  // Maximum purchase amount
    uint256 public constant PRICE_IMPACT_LIMIT = 10;                  // 10% max price impact
    mapping(address => uint256) private _pendingWithdrawals;

    // State variables
    uint256 public virtualTokenReserve;
    uint256 public virtualEthReserve;
    uint256 public totalCollectedETH;

    bool public migrated;
    bool public emergencyMode;

    uint256 public lastActionTimestamp;
    uint256 public constant RATE_LIMIT_INTERVAL = 30; // 30 seconds wait - 1 minutes Change to a higher value for longer waits
    uint256 public constant MAX_ACTIONS_IN_INTERVAL = 3; //  Max 5 purchases per interval - May want to Lower this if needed to 3 actions only
    mapping(address => uint256) public actionCounter;
    mapping(address => uint256) public lastActionTime;

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
            block.timestamp - lastActionTime[user] >= RATE_LIMIT_INTERVAL ||
                actionCounter[user] < MAX_ACTIONS_IN_INTERVAL,
            "ExceededRateLimit"
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
    constructor(address _router, address _factory, address _admin) ERC20("BearedMint", "BMT") { 
        require(_router != address(0), "InvalidAddress");
        require(_factory != address(0), "InvalidAddress");
        require(_admin != address(0), "InvalidAddress");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        
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

        uint256 tokenAmount = calculatePurchaseReturn(msg.value);
        require(tokenAmount > 0, "InvalidAmount");
        
        uint256 maxAllowedPurchase = virtualTokenReserve / 3;  // Reduce max purchase to 33% of available reserve
        require(tokenAmount <= maxAllowedPurchase, "Purchase exceeds allowed limit");
 
        // Ensure enough tokens are available
        require(virtualTokenReserve >= tokenAmount + (virtualTokenReserve / 10), "Not enough tokens in reserve");
        require(totalSupply() + tokenAmount <= TOTAL_SUPPLY, "Amount exceeds totalsupply");    // Check if it exceeds total supply
        
        // Calculate price impact
        uint256 priceImpact = calculatePriceImpact(msg.value, virtualEthReserve);
        require(priceImpact <= PRICE_IMPACT_LIMIT, "Amount exceeds price Imapct");

        // Update reserves
        virtualEthReserve = virtualEthReserve + msg.value;
        virtualTokenReserve = virtualTokenReserve - tokenAmount;
        totalCollectedETH = totalCollectedETH + msg.value;

        bool shouldMigrate = totalSupply() + tokenAmount >= MIGRATION_THRESHOLD;

        _mint(msg.sender, tokenAmount);         // Mint tokens based on celo purchase 10000000000000000

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
        if (tokenAmount == 0) { revert InvalidAmount(); }
        if (balanceOf(msg.sender) < tokenAmount) { revert InsufficientBalance(); }

        uint256 ethAmount = calculateSaleReturn(tokenAmount);
        if (ethAmount == 0) { revert InvalidAmount();}
        if (address(this).balance >= ethAmount) { revert InsufficientBalance();}

        uint256 priceImpact = calculatePriceImpact(ethAmount, virtualEthReserve);
        if (priceImpact > PRICE_IMPACT_LIMIT) { revert ExceedsPriceImpact();}

        _burn(msg.sender, tokenAmount);

        virtualTokenReserve = virtualTokenReserve + tokenAmount;
        virtualEthReserve = virtualEthReserve - ethAmount;
        totalCollectedETH = totalCollectedETH - ethAmount;

        _queueWithdrawal(msg.sender, ethAmount);

        emit TokensSold(msg.sender, tokenAmount, ethAmount);
        emit VirtualReservesUpdated(virtualTokenReserve, virtualEthReserve);
    }

    function _queueWithdrawal(address payee, uint256 amount) private {
        if (payee != address(0)) {revert InvalidAddress();}
        _pendingWithdrawals[payee] = _pendingWithdrawals[payee] + amount;
        emit WithdrawalQueued(payee, amount);
    }

    function withdrawPendingPayments() external nonReentrant {
        uint256 amount = _pendingWithdrawals[msg.sender];
        if (amount == 0) {revert NoPendingPayments();}
        if (address(this).balance < amount) {revert ("Insufficient contract balance");}

        _pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        if (success) {revert ("ETH transfer failed");}

        emit Withdrawn(msg.sender, amount);
    }

    function pendingWithdrawals(address payee) external view returns (uint256) {
        return _pendingWithdrawals[payee];
    }


    /**
    * @notice Calculate the number of tokens to mint based on ETH sent (Bonding Curve Logic)
    * @param ethAmount The amount of ETH sent for purchasing tokens
    * @return The number of tokens to mint 0.01 = 
    */
    function calculatePurchaseReturn(uint256 ethAmount) public view returns (uint256) {
        // uint256 k = virtualTokenReserve * virtualEthReserve;
        // uint256 newVirtualEthReserve = virtualEthReserve + ethAmount;
        // uint256 newVirtualTokenReserve = k / newVirtualEthReserve;
        // return virtualTokenReserve - newVirtualTokenReserve;
        require(ethAmount > 0, "ETH amount must be greater than zero");
        require(virtualTokenReserve > 0, "Insufficient token reserve");

        uint256 newVirtualEthReserve = virtualEthReserve + ethAmount;
        
        // Adjusted formula with an exponential curve instead of purely logarithmic // Logarithmic bonding curve: tokenAmount = C * log(newVirtualEthReserve / virtualEthReserve)
        uint256 tokenAmount = virtualTokenReserve * ((logBase2(newVirtualEthReserve) - logBase2(virtualEthReserve)) ** 2) / 1e18; // 1e18;
        
        require(tokenAmount > 0, "Token purchase amount too low");
        require(tokenAmount < virtualTokenReserve, "Not enough tokens in reserve"); // Prevents depletion
        return tokenAmount;
    }

   /**
    * @notice Calculate the ETH amount returned when selling tokens
    * @param tokenAmount The amount of tokens to sell
    * @return The ETH amount to be returned
    */
   function calculateSaleReturn(uint256 tokenAmount) public view returns (uint256) {
        // uint256 k = virtualTokenReserve * virtualEthReserve;
        // uint256 newVirtualTokenReserve = virtualTokenReserve + (tokenAmount * 5) / 100;
        // uint256 newVirtualEthReserve = k / newVirtualTokenReserve;
        // return virtualEthReserve - newVirtualEthReserve;
        require(tokenAmount > 0, "Token amount must be greater than zero");
        uint256 newVirtualTokenReserve = virtualTokenReserve + tokenAmount;
        
        // Logarithmic bonding curve: ethAmount = C * log(newVirtualTokenReserve / virtualTokenReserve)
        uint256 ethAmount = virtualEthReserve * (logBase2(newVirtualTokenReserve) - logBase2(virtualTokenReserve)) / 1e18;
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
        returns (uint256 tokenAmount, uint256 ethAmount, uint256 liquidity) {
            require(IERC20(address(this)).balanceOf(address(this)) <= preCallTokenBalance, "Token balance manipulated");  // Verify state wasn't manipulated during external call

            address pair = uniswapFactory.getPair(address(this), uniswapRouter.WETH());
            uniswapPair = pair;
            emit MigrationExecuted(ethAmount, tokenAmount, pair);
        } catch {
            // Even if migration fails, we don't want to allow retrying as state has been modified
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


    receive() external payable {
        if (msg.sender == address(uniswapRouter)) {revert ("Only router can send ETH");}
    }
}
