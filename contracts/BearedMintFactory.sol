// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import { BearedMintToken } from "./BearedMintToken.sol";

/**
 * @title BearedMintFactory
 * @notice Factory contract for deploying new BearedMint tokens
 */
contract BearedMintFactory is AccessControl {
    error InvalidAddress();
    error EmptyString();
    error InsufficientBalance();

    using Address for address;

    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    event BearedMintDeployed(address indexed tokenAddress, address indexed owner);

    address public immutable uniswapRouter;
    address public immutable uniswapFactory;

    mapping(address => bool) public isValidBearedMint;

    constructor(address _router, address _factory) {
        if (_router == address(0) || _factory == address(0)) revert InvalidAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEPLOYER_ROLE, msg.sender);

        uniswapRouter = _router;
        uniswapFactory = _factory;
    }

    /**
     * @notice Deploy a new BearedMint token
     * @param admin Address of the token admin
     * @return Address of the deployed token
     */
    function createBearedMint(address admin, string calldata name, string calldata symbol) external payable onlyRole(DEPLOYER_ROLE) returns (address) {
        if (admin == address(0)) revert InvalidAddress();
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert EmptyString();
        if (msg.value < 100 ether) revert InsufficientBalance(); // Match INITIAL_VIRTUAL_ETH_RESERVE

        // Forward ETH to BearedMintToken constructor
        BearedMintToken token = new BearedMintToken{value: msg.value}(
            uniswapRouter,
            uniswapFactory,
            admin
        );

        isValidBearedMint[address(token)] = true;
        emit BearedMintDeployed(address(token), admin);

        return address(token);
    }

    /**
     * @notice Check if an address is a valid BearedMint token
     * @param tokenAddress Address to check
     * @return bool indicating if the address is a valid BearedMint token
     */
    function isValidBearedMintToken(address tokenAddress) external view returns (bool)
    {
        return isValidBearedMint[tokenAddress];
    }
}
