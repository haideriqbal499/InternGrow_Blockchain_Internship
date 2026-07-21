# Task 2 — Automated Token Airdrop & Multi-Send

Payable contract that distributes **ETH or ERC-20 tokens** to many addresses in one transaction.

## Core features

- `airdropEth(recipients)` — equal ETH split
- `airdropToken(token, recipients, totalAmount)` — equal ERC-20 split
- `multiSendEth(recipients, amounts)` — custom amounts
- Dust refund + reentrancy guard

## Upgrade feature — gas efficiency + fail-safes

- Unchecked loop counters
- Low-level `call` with success verification (`TransferFailed(index)`)
- Zero-address / zero-amount checks

## Remix expected output

### Preview (no ETH sent)
`previewEqualSplit(3000000000000000000, 3)` →
```text
amountPerRecipient: 1000000000000000000
remainder: 0
```

### Equal ETH airdrop
Call `airdropEth` with 3 addresses, Value = `0.3 ether`:

```text
amountPer: 100000000000000000   // 0.1 ETH each
refund: 0
```

`getStatus()` afterwards:
```text
ethDistributed: 300000000000000000
airdropCount: 1
contractBalance: 0
```

## File

- `Airdrop.sol`
