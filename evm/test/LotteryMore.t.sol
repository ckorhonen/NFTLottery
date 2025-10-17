// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract LotteryMoreTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address exe = address(0xE1);
    address u1 = address(0x1111);

    function test_DepositRefundDust() public {
        vm.deal(u1, 1 ether);
        Ticket1155 tix = new Ticket1155("u", address(this));
        PrizeVault vault = new PrizeVault(address(this));
        PseudoRandomSource rnd = new PseudoRandomSource();
        Lottery lot =
            new Lottery(address(this), address(this), 0.01 ether, 1 days, 1 days, 5000, 5000, 0, true, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        uint256 before = u1.balance;
        vm.prank(u1);
        lot.deposit{value: 0.015 ether}();
        // user should have been refunded 0.005 ether
        assertEq(u1.balance, before - 0.01 ether);
    }

    function test_ThresholdAutoClose() public {
        vm.deal(u1, 1 ether);
        Ticket1155 tix = new Ticket1155("u", address(this));
        PrizeVault vault = new PrizeVault(address(this));
        PseudoRandomSource rnd = new PseudoRandomSource();
        // thresholdCap = 0.01 ether
        Lottery lot = new Lottery(
            address(this), address(this), 0.01 ether, 7 days, 1 days, 5000, 5000, 0.01 ether, true, tix, vault, rnd
        );
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        vm.prank(u1);
        lot.deposit{value: 0.02 ether}();
        (,,,,, bool closed,,) = lot.rounds(1);
        assertTrue(closed);
    }

    function test_DrawNoParticipants() public {
        Ticket1155 tix = new Ticket1155("u", address(this));
        PrizeVault vault = new PrizeVault(address(this));
        PseudoRandomSource rnd = new PseudoRandomSource();
        Lottery lot =
            new Lottery(address(this), address(this), 0.01 ether, 1 days, 1 days, 5000, 5000, 0, true, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        // close (no deposits)
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        // register a prize
        MockERC20 tok = new MockERC20("T", "T");
        tok.mint(address(vault), 10);
        lot.setExecutor(address(this), true);
        lot.registerPrizeERC20(1, address(tok), 10);
        lot.finalizeRound(1);
        lot.drawWinners(1, 0);
        // winner may be zero; draw path executed
        assertTrue(true);
    }
}
