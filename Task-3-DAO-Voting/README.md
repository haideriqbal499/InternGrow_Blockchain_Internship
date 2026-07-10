# Task 3 - Decentralized Autonomous Voting (DAO)

## Description

This project is a decentralized voting smart contract built using Solidity.

## Features

- Owner creates a poll
- One vote per wallet
- Voting deadline using block.timestamp
- Yes/No voting
- Results tracking
- Events for poll creation, voting, and poll completion

## Functions

### createPoll()

Creates a new voting poll.

### vote()

Allows a wallet to vote once.

### getResults()

Returns the poll question, Yes votes, No votes, and deadline.

### endPoll()

Ends the poll after the deadline.

## Technologies

- Solidity 0.8.20
- Remix IDE
