import { Clarinet, Tx, Chain, types } from "vitest-environment-clarinet";

Clarinet.test({
  name: "Liquidity deposit and withdrawal update pool state",
  async fn(chain: Chain, accounts) {
    const lp = accounts.get("wallet_1")!;

    let block = chain.mineBlock([
      Tx.contractCall(
        "parametric-insurance",
        "deposit-liquidity",
        [types.uint(10_000_000)],
        lp.address
      ),
    ]);

    block.receipts[0].result.expectOk().expectUint(10_000_000);

    const stats = chain.callReadOnlyFn(
      "parametric-insurance",
      "get-pool-stats",
      [],
      lp.address
    );
    stats.result
      .expectOk()
      .expectTuple()["total-liquidity"].expectUint(10_000_000);

    const lpAmount = chain.callReadOnlyFn(
      "parametric-insurance",
      "get-liquidity-of",
      [types.principal(lp.address)],
      lp.address
    );
    lpAmount.result.expectOk().expectUint(10_000_000);

    // withdraw part of liquidity
    block = chain.mineBlock([
      Tx.contractCall(
        "parametric-insurance",
        "withdraw-liquidity",
        [types.uint(5_000_000)],
        lp.address
      ),
    ]);

    block.receipts[0].result.expectOk().expectUint(5_000_000);
  },
});

Clarinet.test({
  name: "Flight delay policy can be bought and paid out when oracle condition is met",
  async fn(chain: Chain, accounts) {
    const deployer = accounts.get("deployer")!;
    const user = accounts.get("wallet_2")!;

    // Seed liquidity pool from deployer
    let block = chain.mineBlock([
      Tx.contractCall(
        "parametric-insurance",
        "deposit-liquidity",
        [types.uint(50_000_000)],
        deployer.address
      ),
    ]);
    block.receipts[0].result.expectOk();

    // User buys a flight-delay policy directly
    block = chain.mineBlock([
      Tx.contractCall(
        "parametric-insurance",
        "buy-flight-policy",
        [
          types.ascii("UA123"), // flight-id
          types.uint(120), // threshold-minutes
          types.uint(1_000_000), // premium (accounting only in this demo)
          types.uint(10_000_000), // payout-amount
        ],
        user.address
      ),
    ]);

    const policyId = block.receipts[0].result.expectOk().expectUint(1);

    // Initially, with no oracle data set, payout should not trigger (returns false)
    block = chain.mineBlock([
      Tx.contractCall(
        "parametric-insurance",
        "check-flight-policy-and-payout",
        [types.uint(policyId)],
        user.address
      ),
    ]);
    block.receipts[0].result.expectOk().expectBool(false);

    // Oracle (any account) sets a delay of 150 minutes for flight UA123
    block = chain.mineBlock([
      Tx.contractCall(
        "oracles",
        "set-flight-delay",
        [types.ascii("UA123"), types.uint(150), types.uint(1_000)],
        deployer.address
      ),
    ]);
    block.receipts[0].result.expectOk();

    // Now the condition should be met and payout should succeed
    block = chain.mineBlock([
      Tx.contractCall(
        "parametric-insurance",
        "check-flight-policy-and-payout",
        [types.uint(policyId)],
        user.address
      ),
    ]);

    block.receipts[0].result.expectOk().expectBool(true);

    // Policy should now be inactive and claimed
    const policy = chain.callReadOnlyFn(
      "parametric-insurance",
      "get-flight-policy",
      [types.uint(policyId)],
      user.address
    );

    const tuple = policy.result.expectOk().expectTuple();
    tuple["active"].expectBool(false);
    tuple["claimed"].expectBool(true);
  },
});
