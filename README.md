# InternGrow — Blockchain Development Track

Solidity smart contracts for the InternGrow Blockchain Development Internship (Module 1).

Built and tested with **Remix IDE** · Solidity **^0.8.20**

## Tasks completed (4/4)

| Task | Folder | Upgrade feature |
|------|--------|-----------------|
| 1. Advanced Storage | `Task-1-AdvancedStorage/` | Ownable + authorized address access control |
| 2. Automated Airdrop & Multi-Send | `Task-2-Airdrop/` | Gas-efficient loops + fail-safe transfer checks |
| 3. DAO Voting | `Task-3-DAO-Voting/` | Multi-poll mappings + token-weighted voting |
| 4. Time-Lock Escrow Vault | `Task-4-TimeLock-Escrow/` | 2-of-3 dual-authorization with arbiter |

## Proper outputs in Remix

Every mutating function **returns decoded values** (visible under “decoded output”), plus events in the tx logs. Use the `get*` / `getStatus` / `preview*` view helpers to print a clear snapshot.

| Task | Best view / return helpers |
|------|----------------------------|
| 1 | `getStatus()`, `store` / `increment` / `decrement` return `newValue` |
| 2 | `previewEqualSplit()`, `getStatus()`, `airdropEth` returns `(amountPer, refund)` |
| 3 | `getResults()`, `getVoterInfo()`, `vote` / `finalizePoll` return tallies + outcome |
| 4 | `getEscrow()`, `approveEarlyRelease` returns approvals + release note |

## How to run (Remix)

1. Open [Remix IDE](https://remix.ethereum.org)
2. Paste the `.sol` file from a task folder
3. Compile with Solidity `0.8.20`
4. Deploy on **Remix VM**
5. Call functions and expand **decoded output** + **logs**
6. Record a short walkthrough for LinkedIn / submission

## Submission checklist

- [x] Complete 2–3+ domain tasks (this repo has **all 4**)
- [ ] Push source to GitHub (`InternGrow_Blockchain_Internship`)
- [ ] Post LinkedIn status tagging `@InternGrow` with repo + demo video
- [ ] Submit via the official WhatsApp Submission Form

## Author

InternGrow Blockchain Development Track · Haider Iqbal
