// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract OneWinEdgeTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address exe = address(0xE1);
    address u1 = address(0x1);

    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
    PseudoRandomSource rnd;

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        // allowMultipleWins = false
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 1 days, 5000, 5000, 0, false, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        lot.setExecutor(exe, true);
        vm.stopPrank();
        vm.deal(u1, 10 ether);
    }

    function test_SingleWallet_MultiplePrizes() public {
        // only one participant buys tickets
        vm.prank(u1); // 10 tickets
        lot.deposit{value: 0.1 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        // register three prizes
        MockERC20 tok = new MockERC20("T", "T");
        tok.mint(address(vault), 30);
        vm.prank(exe);
        lot.registerPrizeERC20(1, address(tok), 10);
        MockERC20 tok2 = new MockERC20("T2", "T2");
        tok2.mint(address(vault), 30);
        vm.prank(exe);
        lot.registerPrizeERC20(1, address(tok2), 10);
        MockERC20 tok3 = new MockERC20("T3", "T3");
        tok3.mint(address(vault), 30);
        vm.prank(exe);
        lot.registerPrizeERC20(1, address(tok3), 10);
        // finalize and draw all
        lot.finalizeRound(1);
        lot.drawWinners(1, 0);
        // all winners should be u1 despite one-win-per-wallet (after attempts exhausted)
        uint256 count = vault.roundPrizeCount(1);
        for (uint256 i = 0; i < count; i++) {
            uint256 idx = vault.prizeIndexAt(1, i);
            (,,,,,, address winner) = _prize(idx);
            assertEq(winner, u1);
        }
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

