# InternGrow Task 2 + Task 3 DApp

One Vite project containing two separate wallet-connected interfaces:

- `/` — Task 2 Airflow airdrop and ERC-20 multi-send
- `/dao-voting.html` — Task 3 LockVote DAO governance

## Run locally

```powershell
npm.cmd install
npm.cmd run dev
```

## Production build

```powershell
npm.cmd run build
```

The pre-build step compiles `Airdrop.sol`, `DAOVoting.sol`, and `TestGovernanceToken.sol`, then Vite emits both pages.

Use MetaMask on Sepolia or another test network.
