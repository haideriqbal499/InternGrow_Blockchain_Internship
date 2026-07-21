# Task 4 — Decentralized Crypto Time-Lock Escrow Vault

Locks ETH using `block.timestamp` until an unlock time. Upgrade: **2-of-3 dual-authorization** (depositor + beneficiary + arbiter) for early release.

## Core features

- `createEscrow(beneficiary, arbiter, lockDurationSeconds)` — payable; locks `msg.value`
- `releaseAfterUnlock(escrowId)` — claim to beneficiary after time lock
- `refundAfterUnlock(escrowId)` — depositor reclaim if still locked past unlock
- `getEscrow(escrowId)` — full status snapshot (status string, seconds left, approvals)

## Upgrade feature — multi-sig dual-authorization

- `approveEarlyRelease(escrowId)` — any party of the three approves
- When **2 of 3** have approved, funds release early to the **beneficiary**
- Arbiter is the trusted third party for dispute resolution / early unlock

## Remix quick test + expected output

### 1) Deploy
Use account **A** (depositor).

### 2) Create escrow
- `beneficiary` = account **B**
- `arbiter` = account **C**
- `lockDurationSeconds` = `60`
- Value = `1 ether`

**decoded output**
```text
escrowId: 0
unlockTime: <now+60>
amount: 1000000000000000000
```

### 3) Check status
Call `getEscrow(0)`:

```text
status: "Locked"
secondsRemaining: ~60
earlyApprovals: 0
canClaimByTime: false
```

### 4) Early release (upgrade path)
- Switch to **C** (arbiter) → `approveEarlyRelease(0)`  
  → `approvals: 1`, `released: false`, `note: "need_2_of_3_approvals"`
- Switch to **B** (beneficiary) → `approveEarlyRelease(0)`  
  → `approvals: 2`, `released: true`, `paidTo: B`, `note: "released_to_beneficiary"`

### 5) Or wait for time unlock
Skip step 4; after 60s call `releaseAfterUnlock(0)` from B → B receives 1 ETH.

## File

- `TimeLockEscrow.sol`
