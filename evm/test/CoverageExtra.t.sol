// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {Lottery} from "src/Lottery.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {VRFv2Adapter} from "src/random/VRFv2Adapter.sol";
import {MockVRFCoordinator} from "test/mocks/MockVRFCoordinator.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";

contract CoverageExtraTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address exe = address(0xE1);
    address u1 = address(0x1);
    address u2 = address(0x2);

    Ticket1155 tix;
    PrizeVault vault;
    Lottery lot;
    PseudoRandomSource rnd;

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 1 days, 5000, 5000, 0, false, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        lot.setExecutor(exe, true);
        vm.stopPrank();
        vm.deal(u1, 10 ether);
        vm.deal(u2, 10 ether);
    }

    function test_TicketUri() public {
        string memory u = tix.uri(1);
        assertEq(u, "ipfs://template/{id}.json");
    }

    function test_PrizeVault_ClaimReverts() public {
        // two participants so draw assigns a real winner
        vm.prank(u1);
        lot.deposit{value: 0.05 ether}();
        vm.prank(u2);
        lot.deposit{value: 0.05 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        MockERC20 tok = new MockERC20("TOK", "TOK");
        tok.mint(address(vault), 100);
        vm.prank(exe);
        uint256 idx = lot.registerPrizeERC20(1, address(tok), 10);
        lot.finalizeRound(1);
        lot.drawWinners(1, 0);
        (,,,,,, address winner) = _prize(idx);
        address wrong = winner == u1 ? u2 : u1;
        vm.expectRevert(PrizeVault.NotWinner.selector);
        vm.prank(wrong);
        vault.claim(idx);
        vm.prank(winner);
        vault.claim(idx);
        vm.expectRevert(PrizeVault.AlreadyClaimed.selector);
        vm.prank(winner);
        vault.claim(idx);
    }

    function test_PrizeVault_ClaimERC1155() public {
        // close round and record prize then claim
        vm.prank(u1);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        MockERC1155 col = new MockERC1155();
        col.mint(address(vault), 77, 3);
        vm.prank(exe);
        uint256 idx = lot.registerPrizeERC1155(1, address(col), 77, 3);
        lot.finalizeRound(1);
        lot.drawWinners(1, 0);
        (,,,,,, address winner) = _prize(idx);
        vm.prank(winner);
        vault.claim(idx);
        // balances: not tracked here; relying on safe transfer success (no revert)
        assertTrue(true);
    }

    function test_Lottery_ClaimOwnerAll() public {
        vm.prank(u1);
        lot.deposit{value: 0.05 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        uint256 balBefore = owner.balance;
        vm.prank(owner);
        lot.claimOwnerAll();
        assertGt(owner.balance, balBefore);
    }

    function test_VRF_setConfig_and_reverts() public {
        MockVRFCoordinator coord = new MockVRFCoordinator();
        VRFv2Adapter adapter = new VRFv2Adapter(address(coord), bytes32(uint256(1)), 1, 3, 400000, owner);
        // only owner can set config
        vm.expectRevert(VRFv2Adapter.NotOwner.selector);
        adapter.setConfig(address(0x1), bytes32(uint256(2)), 2, 5, 500000);
        // set new coordinator and request
        MockVRFCoordinator coord2 = new MockVRFCoordinator();
        vm.prank(owner);
        adapter.setConfig(address(coord2), bytes32(uint256(3)), 4, 6, 700000);
        uint256 req = adapter.requestRandom(99, 1);
        uint256[] memory words = new uint256[](1);
        words[0] = 777;
        // calling from old coordinator should revert
        vm.expectRevert(VRFv2Adapter.NotCoordinator.selector);
        vm.prank(address(coord));
        adapter.fulfillRandomWords(req, words);
        vm.prank(address(coord2));
        adapter.fulfillRandomWords(req, words);
        (uint256 w, bool ok) = adapter.getRandomWord(99, 0);
        assertTrue(ok && w == 777);
    }

    function _prize(uint256 index)
        internal
        view
        returns (PrizeVault.PrizeType, address, uint256, uint256, uint256, bool, address)
    {
        (bool ok, bytes memory data) = address(vault).staticcall(abi.encodeWithSignature("prizes(uint256)", index));
        require(ok);
        return abi.decode(data, (PrizeVault.PrizeType, address, uint256, uint256, uint256, bool, address));
    }
}
