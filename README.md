# TVL Drain Trap

A Drosera trap that detects rapid fund extraction from DeFi protocols by monitoring Total Value Locked (TVL) and triggering on sudden drops that indicate an active exploit.

## Real-World Hack: Wormhole Bridge ($326M Loss)

In February 2022, the Wormhole cross-chain bridge was exploited for approximately **$326 million** when an attacker exploited a signature verification vulnerability to mint 120,000 wETH without depositing any collateral. The attacker then drained the bridge's reserves by redeeming the fraudulently minted tokens. The TVL of the Wormhole bridge dropped by over 90% within minutes as the attacker extracted funds.

TVL drain attacks are the most common outcome of nearly every major DeFi exploit. Whether the root cause is a flash loan attack (Euler Finance, $197M), a bridge vulnerability (Ronin Bridge, $624M), or an access control bug (Nomad Bridge, $190M), the observable effect is always the same: **the protocol's TVL drops sharply in a very short time**. This trap provides a generic "last line of defense" that works regardless of the specific exploit mechanism.

## Attack Vector: Rapid Fund Extraction

TVL drain attacks manifest as the final phase of virtually all DeFi exploits:

1. **Attacker exploits a vulnerability** -- any type: reentrancy, flash loan, oracle manipulation, access control, logic bug, or compromised keys.
2. **Attacker extracts tokens from the protocol** -- calling withdraw, redeem, swap, or a backdoor function to move tokens out of the protocol's vaults and contracts.
3. **Protocol TVL drops sharply** -- the token balance held by the protocol's contracts decreases by a large percentage in a short time window.
4. **Damage compounds** -- if the protocol is not paused, the attacker can repeat the exploit or other attackers can pile in (as seen in the Nomad Bridge free-for-all).

The universal signal: **a sudden, large drop in the protocol's token balance** that far exceeds normal withdrawal patterns.

## How the Trap Works

### Data Collection (`collect()`)

Every block, the trap reads the TVL of the monitored vault:

- **`tvl`** -- The USDC balance held by the monitored vault (`0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2`), measured via `IERC20.balanceOf()` on USDC (`0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`)
- **`blockNumber`** -- The current block number

If the balance call reverts, tvl defaults to zero.

### Trigger Logic (`shouldRespond()`)

The trap implements two detection strategies:

**Condition 1: Single-Block Drain > 20%**

```
drain = previous_tvl - current_tvl
drain_bps = (drain * 10000) / previous_tvl
TRIGGER if drain_bps > 2000 (20%)
```

A 20%+ drop in a single sampling interval is an emergency-level event. Normal protocol operations (user withdrawals, rebalancing) never produce this kind of drop in a single block.

**Condition 2: Cumulative Drain > 30% Across Sample Window**

```
(requires at least 5 data points in the window)
total_drain = oldest_tvl - current_tvl
total_drain_bps = (total_drain * 10000) / oldest_tvl
TRIGGER if total_drain_bps > 3000 (30%)
```

This catches slower drains that might stay below the 20% single-block threshold but accumulate to a dangerous level across the full 10-block sample window. An attacker splitting their exploit across multiple blocks would still be caught.

## Threshold Values

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `DRAIN_THRESHOLD_BPS` | 2000 (20%) | A 20% single-block TVL drop is an extreme outlier. Even during the most volatile market events, protocol TVL does not drop 20% in a single block from organic withdrawals. |
| `ALERT_THRESHOLD_BPS` | 500 (5%) | Defined as a constant for future use as a lower-severity alert threshold. Not currently used in the trigger logic but reserved for tiered alerting. |
| Cumulative drain threshold | 3000 (30%) | A 30% cumulative drain across the sample window (10 blocks, ~2 minutes) catches slower, multi-transaction exploits that individually stay below the 20% threshold. |
| `block_sample_size` | 10 | Provides a ~2-minute window on Ethereum mainnet (12s blocks), long enough to catch multi-block attacks while keeping data fresh. |

## Configuration (`drosera.toml`)

```toml
ethereum_rpc = "https://ethereum-hoodi-rpc.publicnode.com"
drosera_rpc = "https://relay.hoodi.drosera.io"
eth_chain_id = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps.tvl_drain_trap]
path = "out/TVLDrainTrap.sol/TVLDrainTrap.json"
response_contract = "0x0000000000000000000000000000000000000000"
response_function = "emergencyPause()"
cooldown_period_blocks = 33
min_number_of_operators = 1
max_number_of_operators = 2
block_sample_size = 10
private_trap = false
whitelist = []
```

| Field | Description |
|-------|-------------|
| `ethereum_rpc` | RPC endpoint for the Ethereum chain being monitored (Hoodi testnet) |
| `drosera_rpc` | RPC endpoint for the Drosera relay network |
| `eth_chain_id` | Chain ID of the target network |
| `drosera_address` | Address of the Drosera protocol contract |
| `path` | Path to the compiled trap artifact (produced by `forge build`) |
| `response_contract` | Address of the contract to call when the trap triggers (set to zero address as placeholder) |
| `response_function` | Function signature to call on the response contract |
| `cooldown_period_blocks` | Minimum blocks between consecutive responses (prevents spam) |
| `min_number_of_operators` | Minimum Drosera operators required to reach consensus |
| `max_number_of_operators` | Maximum operators that can participate |
| `block_sample_size` | Number of consecutive blocks to collect data for |
| `private_trap` | Whether this trap is restricted to whitelisted operators |

## Architecture

```
+---------------------+         +---------------------+
|   Protocol Vault    |         |   USDC Token        |
| 0x87870Bca3F3f...   |         | 0xA0b86991c621...   |
+----------+----------+         +----------+----------+
           |                               |
           |   balanceOf(vault) ---------->|
           |                               |
           v                               v
+----------+-------------------------------+----------+
|                  TVLDrainTrap                        |
|                                                     |
|  collect():                                         |
|  - tvl (USDC balance in vault)                      |
|  - blockNumber                                      |
+-------------------------+---------------------------+
                          |
                          v
+-------------------------+---------------------------+
|              shouldRespond()                        |
|                                                     |
|  Strategy 1 (Single Block):                         |
|  - Block N vs N-1: drain > 20%?     --> TRIGGER     |
|                                                     |
|  Strategy 2 (Cumulative, 5+ samples):               |
|  - Oldest vs Current: drain > 30%?  --> TRIGGER     |
+-------------------------+---------------------------+
                          |
                          | if triggered
                          v
               +----------+----------+
               |  Response Contract   |
               |  emergencyPause()    |
               +---------------------+
```

## Build

```bash
npm install && forge build
```

## Test

```bash
forge test
```

## Dry Run

```bash
drosera dryrun
```

## Deploy

```bash
export DROSERA_PRIVATE_KEY=<your-private-key>
drosera apply
```

## License

MIT
