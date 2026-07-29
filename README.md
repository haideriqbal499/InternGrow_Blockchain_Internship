# InternGrow — Blockchain Development Track

Secure Solidity contracts and wallet-connected browser interfaces for the InternGrow Blockchain Development Internship.

## Tasks

| Task | Folder | Upgrade |
|------|--------|---------|
| 1. Advanced Storage | `Task-1-AdvancedStorage/` | Owner and authorized-address access control |
| 2. Automated Airdrop | `Task-2-Airdrop/` | Atomic ETH/ERC-20 batches, validation, gas limits, responsive GUI |
| 3. DAO Voting | `Task-3-DAO-Voting/` | ERC-20 locked token-weighted voting, block deadlines, responsive GUI |
| 4. Time-Lock Escrow | `Task-4-TimeLock-Escrow/` | 2-of-3 early-release authorization |

## Run the Task 2 and Task 3 GUIs

```powershell
cd DApp-GUI
npm.cmd install
npm.cmd run dev
```

- Task 2: `http://127.0.0.1:5173/`
- Task 3: `http://127.0.0.1:5173/dao-voting.html`

The build command compiles all included Solidity contracts and creates both production pages:

```powershell
npm.cmd run build
```

Use a test network and test assets when evaluating contract interactions.

## Author

InternGrow Blockchain Development Track · Haider Iqbal
