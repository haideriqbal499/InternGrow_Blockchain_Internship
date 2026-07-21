# Task 3 — Decentralized Autonomous Voting (DAO)

Multi-poll voting with **block-timestamp deadlines**, **one vote per wallet per poll**, and **token-weighted** tallies from locked ETH.

## Core features

- `createPoll(question, durationInMinutes)` → returns `(pollId, deadline)`
- `vote(pollId, support)` — one vote per address; weight = locked balance
- `finalizePoll(pollId)` — locks outcome after deadline
- `getResults` / `getVoterInfo` / `isPollActive`

## Upgrade feature — token-weighted voting

- `lockTokens()` payable — stake ETH for voting power
- Vote weight = locked balance
- `unlockTokens(amount)` returns stake (past votes stay counted)

## Remix expected output

1. Account A: `lockTokens` Value = `2 ether` → `newBalance: 2000000000000000000`
2. Account B: `lockTokens` Value = `1 ether` → `newBalance: 1000000000000000000`
3. Owner: `createPoll("Ship upgrade?", 1)` →
   ```text
   pollId: 0
   deadline: <timestamp>
   ```
4. A: `vote(0, true)` →
   ```text
   weight: 2000000000000000000
   yesVotes: 2000000000000000000
   noVotes: 0
   ```
5. B: `vote(0, false)` →
   ```text
   weight: 1000000000000000000
   yesVotes: 2000000000000000000
   noVotes: 1000000000000000000
   ```
6. After deadline: `finalizePoll(0)` →
   ```text
   yesVotes: 2000000000000000000
   noVotes: 1000000000000000000
   outcome: "YES_WINS"
   ```
7. `getResults(0)` → `status: "finalized"`, `leadingSide: "YES"`

## File

- `DAOVoting.sol`
