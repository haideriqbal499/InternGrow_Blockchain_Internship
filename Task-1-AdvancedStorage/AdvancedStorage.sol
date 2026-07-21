// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Advanced Storage Smart Contract
/// @notice Gas-optimized storage with Ownable + authorized address access control
contract AdvancedStorage {
    address public owner;
    uint256 private storedNumber;

    mapping(address => bool) public authorized;

    event NumberUpdated(uint256 indexed newValue, address indexed updatedBy, string action);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AuthorizationUpdated(address indexed account, bool allowed);

    error NotAuthorized();
    error ZeroAddress();
    error Underflow();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != owner && !authorized[msg.sender]) revert NotAuthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setAuthorized(address account, bool allowed) external onlyOwner returns (bool) {
        if (account == address(0)) revert ZeroAddress();
        authorized[account] = allowed;
        emit AuthorizationUpdated(account, allowed);
        return allowed;
    }

    /// @return newValue The value now stored on-chain
    function store(uint256 number) external onlyAuthorized returns (uint256 newValue) {
        storedNumber = number;
        emit NumberUpdated(number, msg.sender, "store");
        return storedNumber;
    }

    function get() external view returns (uint256 value) {
        return storedNumber;
    }

    /// @return Full readable snapshot for Remix / demos
    function getStatus()
        external
        view
        returns (address currentOwner, uint256 value, bool callerIsOwner, bool callerIsAuthorized)
    {
        return (owner, storedNumber, msg.sender == owner, msg.sender == owner || authorized[msg.sender]);
    }

    function increment() external onlyAuthorized returns (uint256 newValue) {
        unchecked {
            storedNumber++;
        }
        emit NumberUpdated(storedNumber, msg.sender, "increment");
        return storedNumber;
    }

    function decrement() external onlyAuthorized returns (uint256 newValue) {
        if (storedNumber == 0) revert Underflow();
        unchecked {
            storedNumber--;
        }
        emit NumberUpdated(storedNumber, msg.sender, "decrement");
        return storedNumber;
    }
}
