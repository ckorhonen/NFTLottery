// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {CollectionAllowlist, TokenAllowlist} from "src/Allowlists.sol";

contract AllowlistsTest is Test {
    function test_Lists_Set_Length_At() public {
        CollectionAllowlist ca = new CollectionAllowlist(address(this));
        TokenAllowlist ta = new TokenAllowlist(address(this));
        ca.set(address(0x1), true);
        ca.set(address(0x2), false);
        ta.set(address(0xA), true);
        ta.set(address(0xB), true);
        assertEq(ca.length(), 2);
        (address c0, bool a0) = ca.at(0);
        (address c1, bool a1) = ca.at(1);
        assertTrue(c0 != address(0) && c1 != address(0));
        assertTrue(a0 == true || a1 == true);
        assertEq(ta.length(), 2);
        (address t0, bool b0) = ta.at(0);
        (address t1, bool b1) = ta.at(1);
        assertTrue(b0 && b1);
        assertTrue(t0 != address(0) && t1 != address(0));
    }
}

