# Task 1 — Advanced Storage Smart Contract

Gas-optimized Solidity contract to **store**, **read**, **increment**, and **decrement** an integer safely.

## Core features

- `store` / `get` / `increment` / `decrement`
- Unchecked increment + underflow guard on decrement
- Custom errors (cheaper reverts)

## Upgrade feature — Ownable + authorized addresses

- Owner manages `setAuthorized(account, bool)`
- `onlyAuthorized` allows **owner or authorized helpers** to mutate state

## Remix expected output

| Call | Decoded output |
|------|----------------|
| `store(10)` | `newValue: 10` |
| `get()` | `value: 10` |
| `increment()` | `newValue: 11` |
| `decrement()` | `newValue: 10` |
| `getStatus()` | `currentOwner`, `value`, `callerIsOwner`, `callerIsAuthorized` |
| `setAuthorized(0x..., true)` | `true` |

Event log example after `store(10)`:
```text
NumberUpdated(newValue = 10, updatedBy = <you>, action = "store")
```

## File

- `AdvancedStorage.sol`
