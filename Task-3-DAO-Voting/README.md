# Task 3 — Decentralized Autonomous Voting

LockVote is a permissionless, token-weighted DAO polling contract with a responsive MetaMask interface.

## Governance rules

- Voting power equals the caller's locked ERC-20 governance tokens
- One vote per wallet for each poll
- Tokens used for voting remain locked through that poll's deadline
- Deadlines are enforced using block numbers
- Any token locker can create a poll with 2–10 choices
- Anyone can finalize an expired poll
- Poll state, option totals and voting history are stored in secure mappings
- Reentrancy protection and checked ERC-20 transfers protect token custody

`TestGovernanceToken.sol` is included for test networks. Its deployer receives 1,000,000 TEST tokens.

## GUI

The complete Task 3 interface is in `../DApp-GUI/`.

```powershell
cd DApp-GUI
npm.cmd install
npm.cmd run dev
```

Open `http://127.0.0.1:5173/dao-voting.html`, connect MetaMask on Sepolia or another test network, and select **Deploy 1,000,000 TEST**.
