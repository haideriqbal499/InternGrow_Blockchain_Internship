// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Decentralized Crypto Time-Lock Escrow Vault
/// @notice Locks ETH until block.timestamp unlock; 2-of-3 dual-authorization can release early
contract TimeLockEscrow {
    enum EscrowStatus {
        None,
        Locked,
        ReleasedToBeneficiary,
        RefundedToDepositor,
        ResolvedEarly
    }

    struct Escrow {
        address depositor;
        address beneficiary;
        address arbiter;
        uint256 amount;
        uint256 unlockTime;
        EscrowStatus status;
        bool depositorApprovedEarly;
        bool beneficiaryApprovedEarly;
        bool arbiterApprovedEarly;
    }

    uint256 public nextEscrowId;
    mapping(uint256 => Escrow) public escrows;

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed depositor,
        address indexed beneficiary,
        address arbiter,
        uint256 amount,
        uint256 unlockTime
    );
    event EarlyReleaseApproved(uint256 indexed escrowId, address indexed approver, uint256 approvals);
    event EscrowReleased(
        uint256 indexed escrowId,
        address indexed to,
        uint256 amount,
        string reason
    );

    error ZeroAddress();
    error ZeroAmount();
    error InvalidDuration();
    error EscrowMissing();
    error NotLocked();
    error NotParty();
    error StillLocked();
    error AlreadyApproved();
    error TransferFailed();

    /// @notice Lock msg.value until unlockTime = block.timestamp + lockDurationSeconds
    function createEscrow(address beneficiary, address arbiter, uint256 lockDurationSeconds)
        external
        payable
        returns (uint256 escrowId, uint256 unlockTime, uint256 amount)
    {
        if (beneficiary == address(0) || arbiter == address(0)) revert ZeroAddress();
        if (beneficiary == arbiter) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        if (lockDurationSeconds == 0) revert InvalidDuration();

        escrowId = nextEscrowId;
        unchecked {
            nextEscrowId = escrowId + 1;
        }

        unlockTime = block.timestamp + lockDurationSeconds;
        amount = msg.value;

        escrows[escrowId] = Escrow({
            depositor: msg.sender,
            beneficiary: beneficiary,
            arbiter: arbiter,
            amount: amount,
            unlockTime: unlockTime,
            status: EscrowStatus.Locked,
            depositorApprovedEarly: false,
            beneficiaryApprovedEarly: false,
            arbiterApprovedEarly: false
        });

        emit EscrowCreated(escrowId, msg.sender, beneficiary, arbiter, amount, unlockTime);
    }

    /// @notice After unlockTime, beneficiary (or depositor on their behalf) claims funds
    function releaseAfterUnlock(uint256 escrowId) external returns (uint256 amount, address to) {
        Escrow storage e = _requireLocked(escrowId);
        if (block.timestamp < e.unlockTime) revert StillLocked();
        if (msg.sender != e.beneficiary && msg.sender != e.depositor) revert NotParty();

        amount = e.amount;
        to = e.beneficiary;
        e.status = EscrowStatus.ReleasedToBeneficiary;
        e.amount = 0;

        _send(to, amount);
        emit EscrowReleased(escrowId, to, amount, "time_unlock");
    }

    /// @notice After unlock, depositor can reclaim if beneficiary never claimed
    function refundAfterUnlock(uint256 escrowId) external returns (uint256 amount, address to) {
        Escrow storage e = _requireLocked(escrowId);
        if (block.timestamp < e.unlockTime) revert StillLocked();
        if (msg.sender != e.depositor) revert NotParty();

        amount = e.amount;
        to = e.depositor;
        e.status = EscrowStatus.RefundedToDepositor;
        e.amount = 0;

        _send(to, amount);
        emit EscrowReleased(escrowId, to, amount, "depositor_refund_after_unlock");
    }

    /// @notice Upgrade: 2-of-3 dual-authorization early release (depositor / beneficiary / arbiter)
    /// @dev Trusted arbiter can pair with either party to unlock funds early to the beneficiary
    function approveEarlyRelease(uint256 escrowId)
        external
        returns (uint256 approvals, bool released, address paidTo, uint256 amount, string memory note)
    {
        Escrow storage e = _requireLocked(escrowId);

        if (msg.sender == e.depositor) {
            if (e.depositorApprovedEarly) revert AlreadyApproved();
            e.depositorApprovedEarly = true;
        } else if (msg.sender == e.beneficiary) {
            if (e.beneficiaryApprovedEarly) revert AlreadyApproved();
            e.beneficiaryApprovedEarly = true;
        } else if (msg.sender == e.arbiter) {
            if (e.arbiterApprovedEarly) revert AlreadyApproved();
            e.arbiterApprovedEarly = true;
        } else {
            revert NotParty();
        }

        approvals = _approvalCount(e);
        emit EarlyReleaseApproved(escrowId, msg.sender, approvals);

        if (approvals < 2) {
            return (approvals, false, address(0), 0, "need_2_of_3_approvals");
        }

        amount = e.amount;
        paidTo = e.beneficiary;
        e.status = EscrowStatus.ResolvedEarly;
        e.amount = 0;

        _send(paidTo, amount);
        emit EscrowReleased(escrowId, paidTo, amount, "early_dual_authorization");
        return (approvals, true, paidTo, amount, "released_to_beneficiary");
    }

    function getEscrow(uint256 escrowId)
        external
        view
        returns (
            address depositor,
            address beneficiary,
            address arbiter,
            uint256 amount,
            uint256 unlockTime,
            string memory status,
            uint256 secondsRemaining,
            uint256 earlyApprovals,
            bool canClaimByTime
        )
    {
        Escrow storage e = escrows[escrowId];
        if (e.status == EscrowStatus.None && e.depositor == address(0)) revert EscrowMissing();

        depositor = e.depositor;
        beneficiary = e.beneficiary;
        arbiter = e.arbiter;
        amount = e.amount;
        unlockTime = e.unlockTime;
        status = _statusName(e.status);
        earlyApprovals = _approvalCount(e);

        if (e.status == EscrowStatus.Locked && block.timestamp < e.unlockTime) {
            secondsRemaining = e.unlockTime - block.timestamp;
            canClaimByTime = false;
        } else {
            secondsRemaining = 0;
            canClaimByTime = e.status == EscrowStatus.Locked && block.timestamp >= e.unlockTime;
        }
    }

    function getStatusSummary()
        external
        view
        returns (uint256 totalEscrowsCreated, uint256 contractBalance)
    {
        return (nextEscrowId, address(this).balance);
    }

    function _requireLocked(uint256 escrowId) private view returns (Escrow storage e) {
        e = escrows[escrowId];
        if (e.depositor == address(0)) revert EscrowMissing();
        if (e.status != EscrowStatus.Locked) revert NotLocked();
    }

    function _approvalCount(Escrow storage e) private view returns (uint256 count) {
        if (e.depositorApprovedEarly) count++;
        if (e.beneficiaryApprovedEarly) count++;
        if (e.arbiterApprovedEarly) count++;
    }

    function _statusName(EscrowStatus s) private pure returns (string memory) {
        if (s == EscrowStatus.Locked) return "Locked";
        if (s == EscrowStatus.ReleasedToBeneficiary) return "ReleasedToBeneficiary";
        if (s == EscrowStatus.RefundedToDepositor) return "RefundedToDepositor";
        if (s == EscrowStatus.ResolvedEarly) return "ResolvedEarly";
        return "None";
    }

    function _send(address to, uint256 amount) private {
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
