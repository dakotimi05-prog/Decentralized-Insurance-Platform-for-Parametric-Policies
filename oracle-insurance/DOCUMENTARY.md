# Decentralized Parametric Insurance – Documentary

## 1. Story and Motivation

Traditional insurance is slow, opaque, and paperwork-heavy. When something bad
happens – your flight is delayed, your crops fail due to drought, or an
earthquake hits your region – you file a claim and then wait. Adjusters check
receipts, review reports, and subjectively decide whether you should be paid.
The whole process is expensive, manual, and vulnerable to both human error and
fraud.

Parametric insurance flips this model on its head. Instead of arguing about
losses, you and the insurer agree upfront on a simple, external, measurable
condition:

- "If my flight UA123 is delayed by more than 120 minutes, pay me 10 STX."
- "If seasonal rainfall in region X is below Y mm, pay the farmer 1,000 STX."
- "If an earthquake above magnitude 6.0 hits region Y, pay households a fixed
  amount."

Once the condition is met, the policy pays out – automatically and instantly.
There is no claims process and no adjusters. Just data and code.

This project implements that idea on Stacks using Clarity smart contracts and
an on-chain oracle contract.

## 2. High-level Architecture

The project is a Clarinet workspace with three main layers:

1. **Oracles contract (`contracts/oracles.clar`)**
   - A minimal on-chain data registry for real-world events.
   - Stores the latest observation for:
     - Flight delays: `flight-id → delay-minutes, updated-at`.
     - Rainfall: `location + season-id → millimetres, updated-at`.
     - Earthquakes: `region → magnitude*100, updated-at`.
   - In a real deployment, this contract would only be written by a trusted
     oracle service that pulls data from external APIs. In this demo, any
     account can call the setters so the tests and UI can spoof events.

2. **Parametric insurance pool (`contracts/parametric-insurance.clar`)**
   - Manages a shared liquidity pool and flight-delay insurance policies.
   - Key components:
     - **Liquidity pool**
       - `total-liquidity` and `reserved-liquidity` data-vars.
       - `liquidity-providers` map that tracks deposits per principal.
     - **Policies**
       - `flight-policies` map that tracks, for each policy ID:
         - policy owner (principal)
         - flight ID
         - delay threshold in minutes
         - premium (accounting only in this demo)
         - payout amount reserved from the pool
         - status flags `active` and `claimed`.
     - **ID generator**
       - `next-policy-id` auto-increments as new policies are created.

3. **Tests and UI**
   - **Vitest tests** in `tests/parametric-insurance.test.ts` simulate end-to-
     end flows inside the Clarinet simnet:
     - A wallet deposits liquidity.
     - A user buys a flight-delay policy.
     - The oracle reports a delay.
     - The contract evaluates the condition and marks the policy as claimed.
   - **Static UI** in `ui/index.html` is a lightweight playground that builds
     Clarinet-style `Tx.contractCall(...)` lines based on form inputs. You can
     copy these into Clarinet tests or the console to replay scenarios.

## 3. Smart Contract Design

### 3.1 Oracles contract

File: `contracts/oracles.clar`

Core ideas:

- **Data maps**
  - `flight-delays`: keyed by flight ID string.
  - `rainfall`: keyed by `(location, season-id)` pair.
  - `earthquakes`: keyed by region string.
- **Setter functions**
  - `set-flight-delay(flight-id, delay-minutes, timestamp)`
  - `set-rainfall(location, season-id, millimeters, timestamp)`
  - `set-earthquake(region, magnitude-times-100, timestamp)`
- **Read-only views**
  - `get-flight-delay(flight-id)` → latest flight delay data.
  - `get-rainfall(location, season-id)` → rainfall data.
  - `get-earthquake(region)` → last recorded quake magnitude.

The contract does not enforce any access control in this demo. The point is to
show how external data would be structured on-chain and how the insurance
contract can consume it.

### 3.2 Parametric insurance pool contract

File: `contracts/parametric-insurance.clar`

#### Liquidity

- **State**
  - `total-liquidity`: total liquidity accounting in the pool.
  - `reserved-liquidity`: amount already promised to active policies.
  - `liquidity-providers`: how much each principal has supplied.
- **Functions**
  - `deposit-liquidity(amount)`
    - Increments the caller’s balance and `total-liquidity`.
    - Returns `ok new-balance` or `ERR_INVALID_AMOUNT`.
  - `withdraw-liquidity(amount)`
    - Ensures the provider has enough balance and free liquidity is
      sufficient (`ensure-free-liquidity`).
    - Decrements `total-liquidity` and the provider’s share.
    - Returns `ok new-balance` or descriptive error codes.
  - `get-pool-stats()` and `get-liquidity-of(provider)` provide a read-only
    view of the pool.

Note: In a production contract, these functions would also move STX balances
using `stx-transfer?`. In this educational project we keep the focus on the
parametric logic and model the pool as pure accounting state.

#### Flight-delay policies

- **State**
  - `flight-policies` map:
    - `owner`: policy holder principal.
    - `flight-id`: string identifier (e.g. "UA123").
    - `threshold-minutes`: delay threshold to trigger payout.
    - `premium`: premium the user conceptually pays.
    - `payout-amount`: amount reserved from liquidity.
    - `active`, `claimed`: flags representing lifecycle.
  - `next-policy-id`: monotonically increasing uint.

- **Functions**
  - `buy-flight-policy(flight-id, threshold-minutes, premium, payout-amount)`
    - Requires non-zero threshold and payout.
    - Calls `ensure-free-liquidity(payout-amount)` so policies cannot
      over-reserve the pool.
    - Allocates a new policy ID, stores policy details, and increments
      `reserved-liquidity`.
  - `check-flight-policy-and-payout(policy-id)`
    - Looks up the policy by ID and ensures it’s `active` and not `claimed`.
    - Calls `oracles.get-flight-delay(flight-id)` via `contract-call?`.
    - If the oracle returns data and `delay-minutes >= threshold-minutes`:
      - Decrements `reserved-liquidity` and `total-liquidity` by
        `payout-amount`.
      - Marks the policy as `active: false` and `claimed: true`.
      - Returns `ok true`.
    - If the delay is below the threshold, returns `ok false` (policy still
      active, condition not yet met).
    - If the oracle fails or has no data, returns `ERR_ORACLE_ERROR`.

The important property: once the oracle publishes data, the insurance contract
can deterministically and transparently decide whether the payout should occur.
There is no subjective assessment.

## 4. Tests

File: `tests/parametric-insurance.test.ts`

The tests run under `vitest-environment-clarinet`, which spins up a Clarinet
simnet and exposes `Chain`, `Tx`, and helper matchers.

Scenarios covered:

1. **Liquidity flow**
   - A wallet deposits 10,000,000 units into the pool.
   - `get-pool-stats` reports the new `total-liquidity`.
   - `get-liquidity-of` for that wallet returns the correct amount.
   - Withdrawing 5,000,000 units updates balances correctly.

2. **Parametric flight-delay payout**
   - The deployer seeds the pool with liquidity.
   - A second wallet buys a flight-delay policy on flight `UA123` with:
     - threshold = 120 minutes,
     - payout = 10,000,000 units.
   - Initially, without oracle data, `check-flight-policy-and-payout` returns
     `ok false` (condition not met).
   - The oracle contract is called with `set-flight-delay("UA123", 150, ...)`.
   - A second call to `check-flight-policy-and-payout` now returns `ok true`.
   - The read-only `get-flight-policy` shows `active = false` and
     `claimed = true`.

These tests demonstrate both the pool mechanics and the oracle-driven
automation of claims.

## 5. UI Walkthrough

File: `ui/index.html`

This is a static HTML+JS interface meant to sit alongside Clarinet during local
development. It does not talk directly to a Stacks node. Instead, it generates
ready-to-paste calls in the same style used by the Vitest tests.

Sections:

1. **Liquidity Pool**
   - Inputs: liquidity provider principal and amount.
   - Buttons:
     - "Deposit liquidity" → prints a `deposit-liquidity` contract call.
     - "Withdraw 50%" → prints a `withdraw-liquidity` contract call.

2. **Buy Flight-delay Policy**
   - Inputs: policy holder principal, flight ID, delay threshold, premium,
     payout amount.
   - Button:
     - "Buy policy" → prints a `buy-flight-policy` contract call.

3. **Oracle Update & Automated Payout**
   - Inputs: oracle-reported delay (minutes) and policy ID.
   - Buttons:
     - "Update oracle" → prints a `set-flight-delay` call for the given
       flight.
     - "Check policy & payout" → prints a
       `check-flight-policy-and-payout` call.

4. **Event Log**
   - Shows a time-stamped list of all the simulated calls you’ve generated.
   - You can copy any of them straight into a Clarinet test file or the
     console for execution.

This UI satisfies the requirement of having a front-end that “connects” to the
Clarity functions: it makes the contract interactions tangible and re-usable,
without introducing a full-fledged dApp stack.

## 6. Why This Is Cool

- **Objective, data-driven payouts**
  - The claim decision is a pure function of on-chain oracle data and policy
    parameters. Everyone can verify the logic – no hidden rules.

- **Instant, automated execution**
  - As soon as the oracle publishes qualifying data, a single transaction can
    both verify the condition and complete the payout path (in this demo, by
    updating on-chain accounting and policy status).

- **Reduced operational overhead**
  - There is no manual claim intake, document collection, or human review.
    Once a policy is written, the chain handles everything else.

- **Composable building block**
  - The oracle registry and parametric contract are deliberately generic. You
    can extend the same pattern to:
      - rainfall-based crop insurance,
      - earthquake-triggered disaster relief,
      - any other event that can be encoded by an oracle.

- **Transparent incentives**
  - Liquidity providers can see exactly how much capital is total vs reserved
    and what conditions they are exposed to.
  - Policyholders can independently verify that their policy parameters and
    oracle data match the contract’s internal state.

## 7. How to Run

From the `oracle-insurance` directory:

- **Compile and check contracts**

  ```bash
  path=null start=null
  clarinet check
  ```

- **Run tests**

  ```bash
  path=null start=null
  npm test
  ```

- **Open the UI**
  - Serve the `ui` directory with any static file server, for example:

  ```bash
  path=null start=null
  python -m http.server 8000
  ```

  - Then open `http://localhost:8000/ui/index.html` in your browser.

## 8. Possible Extensions

- Add rainfall- and earthquake-based policy maps and functions, mirroring the
  flight-delay design.
- Wire real STX transfers into deposit, withdraw, and payouts using
  `stx-transfer?` and `as-contract`.
- Add on-chain governance so LPs can vote on which oracle feeds and policy
  parameters to accept.
- Build a full dApp front-end that talks to a running Stacks node and wallet
  instead of generating Clarinet test calls.
