// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DAOVoting {

    address public owner;

    struct Poll {
        string question;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 deadline;
        bool exists;
    }

    Poll public poll;

    mapping(address => bool) public hasVoted;

    event PollCreated(string question, uint256 deadline);
    event VoteCast(address voter, bool vote);
    event PollEnded(uint256 yesVotes, uint256 noVotes);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function createPoll(
        string memory _question,
        uint256 durationInMinutes
    ) external onlyOwner {

        require(!poll.exists, "Poll already exists");

        poll = Poll({
            question: _question,
            yesVotes: 0,
            noVotes: 0,
            deadline: block.timestamp + (durationInMinutes * 1 minutes),
            exists: true
        });

        emit PollCreated(_question, poll.deadline);
    }

    function vote(bool _vote) external {

        require(poll.exists, "No active poll");

        require(block.timestamp < poll.deadline, "Voting ended");

        require(!hasVoted[msg.sender], "Already voted");

        hasVoted[msg.sender] = true;

        if(_vote){
            poll.yesVotes++;
        } else {
            poll.noVotes++;
        }

        emit VoteCast(msg.sender, _vote);
    }

    function getResults()
        external
        view
        returns(
            string memory,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            poll.question,
            poll.yesVotes,
            poll.noVotes,
            poll.deadline
        );
    }

    function endPoll() external onlyOwner {

        require(block.timestamp >= poll.deadline, "Voting still active");

        emit PollEnded(
            poll.yesVotes,
            poll.noVotes
        );
    }

}
