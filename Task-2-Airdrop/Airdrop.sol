// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title Automated Token Airdrop & Multi-Send
/// @notice Distributes ETH or ERC-20 tokens equally to many recipients in one tx
contract Airdrop {
    address public owner;
    uint256 public totalEthDistributed;
    uint256 public totalAirdrops;

    event EthAirdropCompleted(
        address indexed sender,
        uint256 recipients,
        uint256 amountPerRecipient,
        uint256 totalSent,
        uint256 refunded
    );
    event TokenAirdropCompleted(
        address indexed sender,
        address indexed token,
        uint256 recipients,
        uint256 amountPerRecipient,
        uint256 totalSent
    );

    error NotOwner();
    error NoRecipients();
    error ZeroAmount();
    error TransferFailed(uint256 index);
    error ArrayLengthMismatch();
    error Reentrancy();
    error InsufficientValue();

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert Reentrancy();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor() {
        owner = msg.sender;
        _status = _NOT_ENTERED;
    }

    /// @notice Preview equal split before sending (view helper for Remix)
    function previewEqualSplit(uint256 totalValue, uint256 recipientCount)
        external
        pure
        returns (uint256 amountPerRecipient, uint256 remainder)
    {
        if (recipientCount == 0) revert NoRecipients();
        amountPerRecipient = totalValue / recipientCount;
        remainder = totalValue - (amountPerRecipient * recipientCount);
    }

    function getStatus()
        external
        view
        returns (address currentOwner, uint256 contractBalance, uint256 ethDistributed, uint256 airdropCount)
    {
        return (owner, address(this).balance, totalEthDistributed, totalAirdrops);
    }

    /// @notice Split msg.value equally; refund leftover dust to sender
    /// @return amountPer Amount each recipient received
    /// @return refund Dust refunded to sender
    function airdropEth(address[] calldata recipients)
        external
        payable
        nonReentrant
        returns (uint256 amountPer, uint256 refund)
    {
        uint256 len = recipients.length;
        if (len == 0) revert NoRecipients();

        amountPer = msg.value / len;
        if (amountPer == 0) revert ZeroAmount();

        for (uint256 i; i < len; ) {
            address to = recipients[i];
            if (to == address(0)) revert TransferFailed(i);

            (bool ok, ) = payable(to).call{value: amountPer}("");
            if (!ok) revert TransferFailed(i);

            unchecked {
                ++i;
            }
        }

        uint256 totalSent = amountPer * len;
        refund = msg.value - totalSent;
        if (refund > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: refund}("");
            if (!refunded) revert TransferFailed(type(uint256).max);
        }

        totalEthDistributed += totalSent;
        unchecked {
            totalAirdrops++;
        }

        emit EthAirdropCompleted(msg.sender, len, amountPer, totalSent, refund);
    }

    function airdropToken(address token, address[] calldata recipients, uint256 totalAmount)
        external
        nonReentrant
        returns (uint256 amountPer, uint256 totalSent)
    {
        uint256 len = recipients.length;
        if (len == 0) revert NoRecipients();
        if (totalAmount == 0) revert ZeroAmount();

        amountPer = totalAmount / len;
        if (amountPer == 0) revert ZeroAmount();

        totalSent = amountPer * len;

        bool pulled = IERC20(token).transferFrom(msg.sender, address(this), totalSent);
        if (!pulled) revert TransferFailed(type(uint256).max);

        for (uint256 i; i < len; ) {
            address to = recipients[i];
            if (to == address(0)) revert TransferFailed(i);

            bool ok = IERC20(token).transfer(to, amountPer);
            if (!ok) revert TransferFailed(i);

            unchecked {
                ++i;
            }
        }

        unchecked {
            totalAirdrops++;
        }

        emit TokenAirdropCompleted(msg.sender, token, len, amountPer, totalSent);
    }

    function multiSendEth(address[] calldata recipients, uint256[] calldata amounts)
        external
        payable
        nonReentrant
        returns (uint256 totalSent, uint256 refund)
    {
        uint256 len = recipients.length;
        if (len == 0) revert NoRecipients();
        if (len != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i; i < len; ) {
            totalSent += amounts[i];
            unchecked {
                ++i;
            }
        }
        if (msg.value < totalSent) revert InsufficientValue();

        for (uint256 i; i < len; ) {
            address to = recipients[i];
            uint256 amount = amounts[i];
            if (to == address(0) || amount == 0) revert TransferFailed(i);

            (bool ok, ) = payable(to).call{value: amount}("");
            if (!ok) revert TransferFailed(i);

            unchecked {
                ++i;
            }
        }

        refund = msg.value - totalSent;
        if (refund > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: refund}("");
            if (!refunded) revert TransferFailed(type(uint256).max);
        }

        totalEthDistributed += totalSent;
        unchecked {
            totalAirdrops++;
        }

        emit EthAirdropCompleted(msg.sender, len, 0, totalSent, refund);
    }

    function rescueEth(address to) external onlyOwner returns (uint256 amount) {
        if (to == address(0)) revert TransferFailed(0);
        amount = address(this).balance;
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed(0);
    }
}
