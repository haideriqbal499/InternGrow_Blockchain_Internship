// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Decentralized Autonomous Voting (DAO)
/// @notice Multi-poll DAO with block-timestamp deadlines and token-weighted voting
contract DAOVoting {
    address public owner;

    struct Poll {
        string question;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 deadline;
        bool exists;
        bool finalized;
    }

    uint256 public nextPollId;
    mapping(uint256 => Poll) public polls;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => uint256) public lockedBalance;
    uint256 public totalLocked;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokensLocked(address indexed account, uint256 amount, uint256 newBalance);
    event TokensUnlocked(address indexed account, uint256 amount, uint256 newBalance);
    event PollCreated(uint256 indexed pollId, string question, uint256 deadline);
    event VoteCast(uint256 indexed pollId, address indexed voter, bool support, uint256 weight);
    event PollFinalized(
        uint256 indexed pollId,
        uint256 yesVotes,
        uint256 noVotes,
        string outcome
    );

    error NotOwner();
    error ZeroAddress();
    error ZeroAmount();
    error AlreadyFinalized();
    error PollMissing();
    error VotingClosed();
    error VotingActive();
    error AlreadyVoted();
    error NoVotingPower();
    error InsufficientLock();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
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

    function lockTokens() external payable returns (uint256 newBalance) {
        if (msg.value == 0) revert ZeroAmount();
        lockedBalance[msg.sender] += msg.value;
        totalLocked += msg.value;
        newBalance = lockedBalance[msg.sender];
        emit TokensLocked(msg.sender, msg.value, newBalance);
    }

    function unlockTokens(uint256 amount) external returns (uint256 newBalance) {
        if (amount == 0) revert ZeroAmount();
        uint256 bal = lockedBalance[msg.sender];
        if (amount > bal) revert InsufficientLock();

        unchecked {
            newBalance = bal - amount;
            lockedBalance[msg.sender] = newBalance;
            totalLocked -= amount;
        }

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit TokensUnlocked(msg.sender, amount, newBalance);
    }

    function createPoll(string calldata question, uint256 durationInMinutes)
        external
        onlyOwner
        returns (uint256 pollId, uint256 deadline)
    {
        if (durationInMinutes == 0) revert ZeroAmount();

        pollId = nextPollId;
        unchecked {
            nextPollId = pollId + 1;
        }

        deadline = block.timestamp + (durationInMinutes * 1 minutes);
        polls[pollId] = Poll({
            question: question,
            yesVotes: 0,
            noVotes: 0,
            deadline: deadline,
            exists: true,
            finalized: false
        });

        emit PollCreated(pollId, question, deadline);
    }

    function vote(uint256 pollId, bool support)
        external
        returns (uint256 weight, uint256 yesVotes, uint256 noVotes)
    {
        Poll storage p = polls[pollId];
        if (!p.exists) revert PollMissing();
        if (block.timestamp >= p.deadline) revert VotingClosed();
        if (hasVoted[pollId][msg.sender]) revert AlreadyVoted();

        weight = lockedBalance[msg.sender];
        if (weight == 0) revert NoVotingPower();

        hasVoted[pollId][msg.sender] = true;

        if (support) {
            p.yesVotes += weight;
        } else {
            p.noVotes += weight;
        }

        yesVotes = p.yesVotes;
        noVotes = p.noVotes;
        emit VoteCast(pollId, msg.sender, support, weight);
    }

    function getResults(uint256 pollId)
        external
        view
        returns (
            string memory question,
            uint256 yesVotes,
            uint256 noVotes,
            uint256 deadline,
            bool finalized,
            string memory status,
            string memory leadingSide
        )
    {
        Poll storage p = polls[pollId];
        if (!p.exists) revert PollMissing();

        if (p.finalized) {
            status = "finalized";
        } else if (block.timestamp >= p.deadline) {
            status = "ended_awaiting_finalize";
        } else {
            status = "active";
        }

        if (p.yesVotes > p.noVotes) {
            leadingSide = "YES";
        } else if (p.noVotes > p.yesVotes) {
            leadingSide = "NO";
        } else {
            leadingSide = "TIE";
        }

        return (p.question, p.yesVotes, p.noVotes, p.deadline, p.finalized, status, leadingSide);
    }

    function getVoterInfo(uint256 pollId, address voter)
        external
        view
        returns (uint256 locked, bool voted, uint256 votingPower)
    {
        locked = lockedBalance[voter];
        voted = hasVoted[pollId][voter];
        votingPower = locked;
    }

    function isPollActive(uint256 pollId) external view returns (bool) {
        Poll storage p = polls[pollId];
        return p.exists && !p.finalized && block.timestamp < p.deadline;
    }

    function finalizePoll(uint256 pollId)
        external
        returns (uint256 yesVotes, uint256 noVotes, string memory outcome)
    {
        Poll storage p = polls[pollId];
        if (!p.exists) revert PollMissing();
        if (block.timestamp < p.deadline) revert VotingActive();
        if (p.finalized) revert AlreadyFinalized();

        p.finalized = true;
        yesVotes = p.yesVotes;
        noVotes = p.noVotes;

        if (yesVotes > noVotes) {
            outcome = "YES_WINS";
        } else if (noVotes > yesVotes) {
            outcome = "NO_WINS";
        } else {
            outcome = "TIE";
        }

        emit PollFinalized(pollId, yesVotes, noVotes, outcome);
    }
}
