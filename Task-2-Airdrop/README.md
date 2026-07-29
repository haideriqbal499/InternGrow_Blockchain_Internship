# Task 2 — Automated Token Airdrop & Multi-Send

A hardened payable contract and MetaMask GUI for distributing ETH or ERC-20 tokens equally to many recipients in one atomic transaction.

## Security and gas features

- Maximum 200 recipients per batch
- Full recipient validation before transfers
- Atomic execution: any failed transfer reverts the complete batch
- Reentrancy protection for ETH and token paths
- ERC-20 balance and allowance verification
- Compatibility with tokens that return `true` or no transfer data
- Direct `transferFrom` from sender to recipients
- Exact equal splits with ETH dust refunds
- Unchecked loop increments and cached lengths

## GUI

The complete Task 2 interface is in `../DApp-GUI/`.

```powershell
cd DApp-GUI
npm.cmd install
npm.cmd run dev
```

Open `http://127.0.0.1:5173/`.
