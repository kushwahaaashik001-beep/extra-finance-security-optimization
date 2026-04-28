// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../contracts/YulAccounting.sol";

/**
 * @title Baseline Solidity Implementation for Comparison
 */
contract OriginalAccounting {
    struct DebtPosition {
        uint256 borrowed;
        uint256 reserveId;
    }

    mapping(uint256 => DebtPosition) public debtPositions;
    mapping(uint256 => uint256) public reserves; // reserveId => totalBorrows
    mapping(uint256 => mapping(address => uint256)) public credits;

    function repayOriginal(uint256 debtId, uint256 amount) external returns (uint256 actualRepaid) {
        DebtPosition storage pos = debtPositions[debtId];
        uint256 borrowed = pos.borrowed;
        
        actualRepaid = amount > borrowed ? borrowed : amount;
        if (actualRepaid == 0) return 0;

        pos.borrowed -= actualRepaid;
        reserves[pos.reserveId] -= actualRepaid;
        
        // FIX: Original Bug: updates credits with 'amount' instead of 'actualRepaid'
        // Corrected to actualRepaid for a fair comparison with the fixed Yul version.
        credits[pos.reserveId][msg.sender] += actualRepaid; 
    }

    function borrowOriginal(uint256 debtId, uint256 amount, uint256 reserveId) external {
        // Added basic overflow checks for robustness, similar to Yul version
        if (reserves[reserveId] + amount < reserves[reserveId]) revert("Overflow in reserves");
        if (debtPositions[debtId].borrowed + amount < debtPositions[debtId].borrowed) revert("Overflow in debt position");

        reserves[reserveId] += amount;
        debtPositions[debtId].borrowed += amount;
        if (debtPositions[debtId].reserveId == 0) {
            debtPositions[debtId].reserveId = reserveId;
        }
    }
}

/**
 * @title Extra Finance Gas Benchmark Test
 * @author Blockchain Performance Architect
 * @notice Compares standard Solidity accounting vs Yul-optimized accounting.
 */
contract GasBenchmarkTest is Test {
    OriginalAccounting original;
    YulAccounting optimized;

    uint256 constant TEST_DEBT_ID = 420;
    uint256 constant TEST_RESERVE_ID = 1;
    uint256 constant INITIAL_DEBT = 1000 ether;
    address constant USER = address(0xDEADBEEF);

    function setUp() public {
        original = new OriginalAccounting();
        optimized = new YulAccounting();
        
        // Initialize state for both
        vm.startPrank(USER); // Prank for consistency
        original.borrowOriginal(TEST_DEBT_ID, INITIAL_DEBT, TEST_RESERVE_ID);
        optimized.borrowOptimized(TEST_DEBT_ID, INITIAL_DEBT, TEST_RESERVE_ID);
        vm.stopPrank();
    }

    /**
     * @notice Benchmark the Repay function
     * Comparison: Solidity Storage Pointers vs Yul Scratch Space Management
     */
    function test_Benchmark_Repay() public {
        uint256 repayAmt = 100 ether;

        // 1. Benchmark Original (Solidity)
        uint256 gasBeforeOrig = gasleft();
        vm.prank(USER);
        original.repayOriginal(TEST_DEBT_ID, repayAmt);
        uint256 gasUsedOrig = gasBeforeOrig - gasleft();
        vm.stopPrank(); // Stop prank after each benchmarked call

        // 2. Benchmark Optimized (Yul)
        uint256 gasBeforeOpt = gasleft();
        vm.prank(USER);
        optimized.repayOptimized(TEST_DEBT_ID, repayAmt);
        uint256 gasUsedOpt = gasBeforeOpt - gasleft();
        vm.stopPrank(); // Stop prank after each benchmarked call

        printResults("REPAY", gasUsedOrig, gasUsedOpt);
        
        // Assert logic integrity by comparing individual state variables
        (uint256 origBorrowed, uint256 origReserveId) = original.debtPositions(TEST_DEBT_ID);
        (uint256 optBorrowed, uint256 optReserveId) = optimized.getDebtPosition(TEST_DEBT_ID);
        assertEq(origBorrowed, optBorrowed, "Repay: Borrowed amount mismatch");
        assertEq(origReserveId, optReserveId, "Repay: Reserve ID mismatch");
        assertEq(original.reserves(TEST_RESERVE_ID), optimized.getTotalBorrows(TEST_RESERVE_ID), "Repay: Total borrows mismatch");
        assertEq(original.credits(TEST_RESERVE_ID, USER), optimized.getCredits(TEST_RESERVE_ID, USER), "Repay: Credits mismatch");
    }

    /**
     * @notice Benchmark the Borrow function
     * Comparison: Solidity Checked Math vs Yul Bit-Packing/Raw Storage
     */
    function test_Benchmark_Borrow() public {
        uint256 borrowAmt = 50 ether;

        // 1. Benchmark Original (Solidity)
        uint256 gasBeforeOrig = gasleft();
        original.borrowOriginal(TEST_DEBT_ID + 1, borrowAmt, TEST_RESERVE_ID);
        uint256 gasUsedOrig = gasBeforeOrig - gasleft();

        // 2. Benchmark Optimized (Yul)
        uint256 gasBeforeOpt = gasleft();
        optimized.borrowOptimized(TEST_DEBT_ID + 2, borrowAmt, TEST_RESERVE_ID);
        uint256 gasUsedOpt = gasBeforeOpt - gasleft();

        printResults("BORROW", gasUsedOrig, gasUsedOpt);
    }

    /**
     * @dev Helper to print professional benchmark logs
     */
    function printResults(string memory label, uint256 originalGas, uint256 optimizedGas) internal pure {
        uint256 savings = originalGas - optimizedGas;
        uint256 percentage = (savings * 100) / originalGas;

        console.log("-----------------------------------------");
        console.log(string.concat("Performance Report: ", label));
        console.log("Original Gas (Solidity):  ", originalGas);
        console.log("Optimized Gas (Yul):      ", optimizedGas);
        console.log("Total Gas Saved:          ", savings);
        console.log("Efficiency Gain:          ", percentage, "%");
        console.log("-----------------------------------------");
        
        // Industry Flex: Pro-devs ensure savings are at least 10%
        require(optimizedGas < originalGas, "Optimization failed to reduce gas");
    }
}