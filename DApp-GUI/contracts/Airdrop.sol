// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @title Airflow - Automated Token Airdrop & Multi-Send
/// @notice Atomically distributes ETH or ERC-20 tokens equally across a validated batch.
contract Airdrop {
    uint256 public constant MAX_RECIPIENTS = 200;

    address public immutable owner;
    uint256 public totalEthDistributed;
    uint256 public totalTokenDistributed;
    uint256 public totalAirdrops;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    event EthAirdropCompleted(address indexed sender, uint256 recipients, uint256 amountPerRecipient, uint256 totalSent, uint256 refunded);
    event TokenAirdropCompleted(address indexed sender, address indexed token, uint256 recipients, uint256 amountPerRecipient, uint256 totalSent);

    error NoRecipients();
    error TooManyRecipients(uint256 supplied, uint256 maximum);
    error InvalidRecipient(uint256 index);
    error InvalidToken();
    error ZeroAmount();
    error InsufficientTokenBalance(uint256 available, uint256 required);
    error InsufficientAllowance(uint256 available, uint256 required);
    error TransferFailed(uint256 index);
    error RefundFailed();
    error Reentrancy();

    modifier nonReentrant() {
        if (_status == _ENTERED) revert Reentrancy();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor() { owner = msg.sender; }

    function previewEqualSplit(uint256 totalValue, uint256 recipientCount)
        external pure returns (uint256 amountPerRecipient, uint256 remainder)
    {
        _validateCount(recipientCount);
        amountPerRecipient = totalValue / recipientCount;
        if (amountPerRecipient == 0) revert ZeroAmount();
        remainder = totalValue - (amountPerRecipient * recipientCount);
    }

    function getStatus()
        external view
        returns (uint256 contractBalance, uint256 ethDistributed, uint256 tokenDistributed, uint256 airdropCount)
    {
        return (address(this).balance, totalEthDistributed, totalTokenDistributed, totalAirdrops);
    }

    /// @notice Splits msg.value equally and refunds indivisible wei to the sender.
    function airdropEth(address[] calldata recipients)
        external payable nonReentrant returns (uint256 amountPerRecipient, uint256 refund)
    {
        uint256 length = recipients.length;
        _validateRecipients(recipients, length);
        amountPerRecipient = msg.value / length;
        if (amountPerRecipient == 0) revert ZeroAmount();

        uint256 totalSent = amountPerRecipient * length;
        refund = msg.value - totalSent;
        for (uint256 i; i < length;) {
            (bool sent,) = payable(recipients[i]).call{value: amountPerRecipient}("");
            if (!sent) revert TransferFailed(i);
            unchecked { ++i; }
        }
        if (refund != 0) {
            (bool refunded,) = payable(msg.sender).call{value: refund}("");
            if (!refunded) revert RefundFailed();
        }

        totalEthDistributed += totalSent;
        unchecked { ++totalAirdrops; }
        emit EthAirdropCompleted(msg.sender, length, amountPerRecipient, totalSent, refund);
    }

    /// @notice Sends equal ERC-20 shares directly from the sender to every recipient.
    function airdropToken(address token, address[] calldata recipients, uint256 totalAmount)
        external nonReentrant returns (uint256 amountPerRecipient, uint256 totalSent)
    {
        if (token.code.length == 0) revert InvalidToken();
        uint256 length = recipients.length;
        _validateRecipients(recipients, length);
        amountPerRecipient = totalAmount / length;
        if (amountPerRecipient == 0) revert ZeroAmount();
        totalSent = amountPerRecipient * length;

        uint256 balance = _readUint(token, abi.encodeCall(IERC20.balanceOf, (msg.sender)));
        if (balance < totalSent) revert InsufficientTokenBalance(balance, totalSent);
        uint256 approved = _readUint(token, abi.encodeCall(IERC20.allowance, (msg.sender, address(this))));
        if (approved < totalSent) revert InsufficientAllowance(approved, totalSent);

        for (uint256 i; i < length;) {
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(0x23b872dd, msg.sender, recipients[i], amountPerRecipient)
            );
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed(i);
            unchecked { ++i; }
        }

        totalTokenDistributed += totalSent;
        unchecked { ++totalAirdrops; }
        emit TokenAirdropCompleted(msg.sender, token, length, amountPerRecipient, totalSent);
    }

    function _validateRecipients(address[] calldata recipients, uint256 length) private pure {
        _validateCount(length);
        for (uint256 i; i < length;) {
            if (recipients[i] == address(0)) revert InvalidRecipient(i);
            unchecked { ++i; }
        }
    }

    function _validateCount(uint256 length) private pure {
        if (length == 0) revert NoRecipients();
        if (length > MAX_RECIPIENTS) revert TooManyRecipients(length, MAX_RECIPIENTS);
    }

    function _readUint(address token, bytes memory payload) private view returns (uint256 value) {
        (bool success, bytes memory data) = token.staticcall(payload);
        if (!success || data.length < 32) revert InvalidToken();
        value = abi.decode(data, (uint256));
    }
}
