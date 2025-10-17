// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {VRFv2Adapter} from "src/random/VRFv2Adapter.sol";
import {MockVRFCoordinator} from "test/mocks/MockVRFCoordinator.sol";

contract VRFAdapterTest is Test {
    VRFv2Adapter adapter;
    MockVRFCoordinator coord;
    address owner = address(this);

    function setUp() public {
        coord = new MockVRFCoordinator();
        adapter = new VRFv2Adapter(address(coord), bytes32(uint256(1)), 1, 3, 400000, owner);
    }

    function test_RequestAndFulfill() public {
        uint256 reqId = adapter.requestRandom(42, 2);
        assertEq(reqId, 1);
        // coordinator fulfills
        uint256[] memory words = new uint256[](2);
        words[0] = 111;
        words[1] = 222;
        vm.prank(address(coord));
        adapter.fulfillRandomWords(reqId, words);
        (uint256 w0, bool ok0) = adapter.getRandomWord(42, 0);
        (uint256 w1, bool ok1) = adapter.getRandomWord(42, 1);
        assertTrue(ok0 && ok1);
        assertEq(w0, 111);
        assertEq(w1, 222);
    }
}

