// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Trap} from "drosera-contracts/Trap.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title TVLDrainTrap
/// @notice Detects rapid fund extraction from any protocol
/// @dev Monitors protocol TVL and triggers on >20% drop between blocks

struct CollectOutput {
    uint256 tvl;
    uint256 blockNumber;
}

contract TVLDrainTrap is Trap {
    // Protocol vault/contract holding funds
    address public constant MONITORED_VAULT = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    // Token to monitor balance of (USDC)
    address public constant MONITORED_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // 20% drain threshold
    uint256 public constant DRAIN_THRESHOLD_BPS = 2000;
    // 5% alert threshold
    uint256 public constant ALERT_THRESHOLD_BPS = 500;

    constructor() {}

    function collect() external view override returns (bytes memory) {
        uint256 tvl;

        try IERC20(MONITORED_TOKEN).balanceOf(MONITORED_VAULT) returns (uint256 balance) {
            tvl = balance;
        } catch {
            tvl = 0;
        }

        return abi.encode(CollectOutput({
            tvl: tvl,
            blockNumber: block.number
        }));
    }

    function shouldRespond(
        bytes[] calldata data
    ) external pure override returns (bool, bytes memory) {
        if (data.length < 2) return (false, bytes(""));

        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));

        // Skip if previous TVL was 0
        if (previous.tvl == 0) return (false, bytes(""));

        // Check for TVL decrease
        if (current.tvl < previous.tvl) {
            uint256 drain = previous.tvl - current.tvl;
            uint256 drainBps = (drain * 10000) / previous.tvl;

            // Critical: >20% drain in one sample — emergency response
            if (drainBps > DRAIN_THRESHOLD_BPS) {
                return (true, bytes("CRITICAL: TVL drained >20% - emergency pause required"));
            }
        }

        // Also check cumulative drain across the full sample window
        if (data.length >= 5) {
            CollectOutput memory oldest = abi.decode(data[data.length - 1], (CollectOutput));
            if (oldest.tvl > 0 && current.tvl < oldest.tvl) {
                uint256 totalDrain = oldest.tvl - current.tvl;
                uint256 totalDrainBps = (totalDrain * 10000) / oldest.tvl;

                // >30% cumulative drain across window
                if (totalDrainBps > 3000) {
                    return (true, bytes("CRITICAL: Cumulative TVL drain >30% across sample window"));
                }
            }
        }

        return (false, bytes(""));
    }
}
