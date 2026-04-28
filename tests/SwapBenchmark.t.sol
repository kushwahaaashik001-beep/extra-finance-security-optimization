// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/SwapGuard.sol";

contract SwapBenchmarkTest is Test {
    SwapGuard public guard;

    function setUp() public {
        guard = new SwapGuard();
    }

    function test_RevertIf_PoolManipulated() public {
        // Directly expecting the raw 4-byte selector to bypass Foundry's internal ABI resolution.
        // This ensures a direct byte-for-byte match with the contract's revert data.
        vm.expectRevert(bytes4(0x29587ad0));
        
        // Trigger the high-performance guard check
        guard.checkReserves(address(0x123));
    }
}