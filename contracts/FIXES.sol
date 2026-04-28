// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./libraries/types/DataTypes.sol";

/**
 * @title Extra Finance Optimized Accounting (Secure V2 - Production Grade)
 * @notice Mitigates Unlimited Credit Exploit & Rounding Underflows via Yul.
 * @dev Implementation achieves extreme gas efficiency by bypassing Solidity's high-level event encoding.
 */
abstract contract LendingPoolFixes {
    mapping(uint256 => DataTypes.DebtPositionData) public debtPositions;
    mapping(uint256 => DataTypes.ReserveData) public reserves;
    mapping(uint256 => mapping(address => uint256)) public credits;

    // Error declarations for Yul visibility
    error ZeroAmount();

    // Events for protocol integrity
    event Repay(uint256 indexed debtId, address indexed onBehalfOf, uint256 actualAmount);
    event Borrow(uint256 indexed debtId, address indexed onBehalfOf, uint256 amount);

    /**
     * @notice Secure Repay with Capped Credits & Underflow Protection.
     * @dev Fixes critical accounting mismatch where raw 'amount' inflated credits.
     */
    function _repayOptimized(address onBehalfOf, uint256 debtId, uint256 amount) internal returns (uint256 actualRepaid) {
        DataTypes.DebtPositionData storage debtPosition = debtPositions[debtId];
        DataTypes.ReserveData storage reserve = reserves[debtPosition.reserveId];

        assembly {
            let debtSlot := debtPosition.slot
            let reserveSlot := reserve.slot

            // Load state
            let borrowed := sload(add(debtSlot, 2))
            let totalBorrows := sload(add(reserveSlot, 2))

            // CRITICAL FIX: actualRepaid = min(amount, borrowed, totalBorrows)
            // This prevents phantom credit inflation AND rounding errors.
            actualRepaid := amount
            if gt(actualRepaid, borrowed) { actualRepaid := borrowed }
            if gt(actualRepaid, totalBorrows) { actualRepaid := totalBorrows }

            if iszero(actualRepaid) {
                // Revert with ZeroAmount() selector 0x1f2a3482
                mstore(0x00, 0x1f2a348200000000000000000000000000000000000000000000000000000000)
                revert(0x00, 0x04)
            }

            // State Updates
            sstore(add(debtSlot, 2), sub(borrowed, actualRepaid))
            sstore(add(reserveSlot, 2), sub(totalBorrows, actualRepaid))

            // Update Credits: credits[reserveId][onBehalfOf]
            let resId := sload(debtSlot)
            mstore(0x00, resId)
            mstore(0x20, credits.slot)
            let innerHash := keccak256(0, 64)
            mstore(0x00, onBehalfOf)
            mstore(0x20, innerHash)
            let creditSlot := keccak256(0, 64)
            sstore(creditSlot, add(sload(creditSlot), actualRepaid))

            // LOGGING: Repay(uint256,address,uint256)
            mstore(0x00, actualRepaid) // Non-indexed data
            log3(
                0x00, 0x20, // Data location and size
                0x3e404b86a8775f0a202410a8d672958763567d264f33b1e368735232a9ba954a, // Topic 0
                debtId,     // Topic 1
                onBehalfOf  // Topic 2
            )
        }
    }

    /**
     * @notice Optimized Borrow with Stale Interest Prevention.
     */
    function _borrowOptimized(address onBehalfOf, uint256 debtId, uint256 amount) internal {
        DataTypes.DebtPositionData storage debtPosition = debtPositions[debtId];
        DataTypes.ReserveData storage reserve = reserves[debtPosition.reserveId];

        assembly {
            let debtSlot := debtPosition.slot
            let reserveSlot := reserve.slot

            let borrowed := sload(add(debtSlot, 2))
            let totalBorrows := sload(add(reserveSlot, 2))

            // Accounting
            sstore(add(debtSlot, 2), add(borrowed, amount))
            sstore(add(reserveSlot, 2), add(totalBorrows, amount))

            // Sync lastUpdateTimestamp (Slot 11 in ReserveData)
            let timestampSlot := add(reserveSlot, 11)
            let timestampVal := sload(timestampSlot)
            let mask := 0xffffffffffffffffffffffffffffffff
            let newTimestamp := or(and(timestampVal, not(mask)), and(timestamp(), mask))
            sstore(timestampSlot, newTimestamp)

            // LOGGING: Borrow(uint256,address,uint256)
            mstore(0x00, amount)
            log3(
                0x00, 0x20,
                0x1384061a91e0a9693ed8a83a0a383d47d4e5f29d107a67035f6f4f22c1935825,
                debtId,
                onBehalfOf
            )
        }
    }
}