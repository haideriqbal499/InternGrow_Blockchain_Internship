// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20VotingToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title LockVote DAO
/// @notice Token-weighted polling where voting power must remain locked until a poll ends.
contract DAOVoting {
    uint256 public constant MAX_OPTIONS = 10;
    uint256 public constant MAX_DURATION_BLOCKS = 1_000_000;

    struct Poll {
        address creator;
        string title;
        string description;
        uint64 startBlock;
        uint64 deadlineBlock;
        uint16 optionCount;
        bool active;
        uint256 totalVotingPower;
        uint256 voterCount;
    }

    IERC20VotingToken public immutable votingToken;
    uint256 public pollCount;
    uint256 private _entered;

    mapping(uint256 pollId => Poll poll) private _polls;
    mapping(uint256 pollId => mapping(uint256 optionId => string name)) private _optionNames;
    mapping(uint256 pollId => mapping(uint256 optionId => uint256 votes)) private _optionVotes;
    mapping(uint256 pollId => mapping(address voter => bool voted)) public hasVoted;
    mapping(address voter => uint256 amount) public lockedBalance;
    mapping(address voter => uint256 blockNumber) public unlockBlock;

    event TokensLocked(address indexed voter, uint256 amount, uint256 newBalance);
    event TokensUnlocked(address indexed voter, uint256 amount, uint256 newBalance);
    event PollCreated(uint256 indexed pollId, address indexed creator, uint256 deadlineBlock, string title);
    event VoteCast(uint256 indexed pollId, address indexed voter, uint256 indexed optionId, uint256 votingPower);
    event PollClosed(uint256 indexed pollId);

    error InvalidToken();
    error InvalidAmount();
    error InvalidPoll();
    error InvalidOption();
    error InvalidDuration();
    error InvalidOptionCount();
    error EmptyTitle();
    error EmptyOption(uint256 index);
    error PollNotActive();
    error PollStillOpen();
    error PollExpired();
    error AlreadyVoted();
    error NoVotingPower();
    error TokensStillCommitted(uint256 untilBlock);
    error InsufficientLockedBalance();
    error TokenTransferFailed();
    error Reentrancy();

    modifier nonReentrant() {
        if (_entered == 1) revert Reentrancy();
        _entered = 1;
        _;
        _entered = 0;
    }

    constructor(address token) {
        if (token == address(0) || token.code.length == 0) revert InvalidToken();
        votingToken = IERC20VotingToken(token);
    }

    function lockTokens(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 balanceBefore = votingToken.balanceOf(address(this));
        _safeTransferFrom(msg.sender, address(this), amount);
        if (votingToken.balanceOf(address(this)) - balanceBefore != amount) revert TokenTransferFailed();
        lockedBalance[msg.sender] += amount;
        emit TokensLocked(msg.sender, amount, lockedBalance[msg.sender]);
    }

    function unlockTokens(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        uint256 balance = lockedBalance[msg.sender];
        if (amount > balance) revert InsufficientLockedBalance();
        if (block.number <= unlockBlock[msg.sender]) revert TokensStillCommitted(unlockBlock[msg.sender]);
        unchecked {
            lockedBalance[msg.sender] = balance - amount;
        }
        _safeTransfer(msg.sender, amount);
        emit TokensUnlocked(msg.sender, amount, lockedBalance[msg.sender]);
    }

    /// @notice Poll creation is permissionless for wallets with locked governance tokens.
    function createPoll(
        string calldata title,
        string calldata description,
        string[] calldata options,
        uint64 durationBlocks
    ) external returns (uint256 pollId) {
        if (lockedBalance[msg.sender] == 0) revert NoVotingPower();
        if (bytes(title).length == 0) revert EmptyTitle();
        if (durationBlocks == 0 || durationBlocks > MAX_DURATION_BLOCKS) revert InvalidDuration();
        uint256 optionCount = options.length;
        if (optionCount < 2 || optionCount > MAX_OPTIONS) revert InvalidOptionCount();

        pollId = ++pollCount;
        uint256 deadline = block.number + durationBlocks;
        Poll storage poll = _polls[pollId];
        poll.creator = msg.sender;
        poll.title = title;
        poll.description = description;
        poll.startBlock = uint64(block.number);
        poll.deadlineBlock = uint64(deadline);
        poll.optionCount = uint16(optionCount);
        poll.active = true;

        for (uint256 i; i < optionCount;) {
            if (bytes(options[i]).length == 0) revert EmptyOption(i);
            _optionNames[pollId][i] = options[i];
            unchecked { ++i; }
        }
        emit PollCreated(pollId, msg.sender, deadline, title);
    }

    /// @notice Casts one token-weighted vote and commits its tokens through the deadline.
    function vote(uint256 pollId, uint256 optionId) external {
        Poll storage poll = _polls[pollId];
        if (poll.creator == address(0)) revert InvalidPoll();
        if (!poll.active) revert PollNotActive();
        if (block.number > poll.deadlineBlock) revert PollExpired();
        if (optionId >= poll.optionCount) revert InvalidOption();
        if (hasVoted[pollId][msg.sender]) revert AlreadyVoted();

        uint256 power = lockedBalance[msg.sender];
        if (power == 0) revert NoVotingPower();
        hasVoted[pollId][msg.sender] = true;
        _optionVotes[pollId][optionId] += power;
        poll.totalVotingPower += power;
        poll.voterCount += 1;
        if (unlockBlock[msg.sender] < poll.deadlineBlock) unlockBlock[msg.sender] = poll.deadlineBlock;
        emit VoteCast(pollId, msg.sender, optionId, power);
    }

    /// @notice Marks an expired poll inactive. Anyone may perform this cleanup.
    function closePoll(uint256 pollId) external {
        Poll storage poll = _polls[pollId];
        if (poll.creator == address(0)) revert InvalidPoll();
        if (!poll.active) revert PollNotActive();
        if (block.number <= poll.deadlineBlock) revert PollStillOpen();
        poll.active = false;
        emit PollClosed(pollId);
    }

    function getPoll(uint256 pollId) external view returns (Poll memory) {
        if (_polls[pollId].creator == address(0)) revert InvalidPoll();
        return _polls[pollId];
    }

    function getOptions(uint256 pollId)
        external
        view
        returns (string[] memory names, uint256[] memory votes)
    {
        Poll storage poll = _polls[pollId];
        if (poll.creator == address(0)) revert InvalidPoll();
        uint256 count = poll.optionCount;
        names = new string[](count);
        votes = new uint256[](count);
        for (uint256 i; i < count;) {
            names[i] = _optionNames[pollId][i];
            votes[i] = _optionVotes[pollId][i];
            unchecked { ++i; }
        }
    }

    function isPollOpen(uint256 pollId) external view returns (bool) {
        Poll storage poll = _polls[pollId];
        return poll.active && block.number <= poll.deadlineBlock;
    }

    function _safeTransfer(address to, uint256 amount) private {
        (bool success, bytes memory data) =
            address(votingToken).call(abi.encodeCall(IERC20VotingToken.transfer, (to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed();
    }

    function _safeTransferFrom(address from, address to, uint256 amount) private {
        (bool success, bytes memory data) =
            address(votingToken).call(abi.encodeCall(IERC20VotingToken.transferFrom, (from, to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed();
    }
}
