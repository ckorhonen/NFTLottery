// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {LotteryAutomation} from "src/automation/LotteryAutomation.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract AutomationTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address exe = address(0xE1);
    address user = address(0xBEEF);

    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
    PseudoRandomSource rnd;
    LotteryAutomation autoC;

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 1 days, 5000, 5000, 0, true, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        lot.setExecutor(exe, true);
        autoC = new LotteryAutomation(address(lot), address(vault), owner);
        vm.stopPrank();
        vm.deal(user, 1 ether);
    }

    function test_Automation_Flow() public {
        // deposit
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        // nothing to do yet
        (bool need, bytes memory data) = autoC.checkUpkeep("");
        assertTrue(!need);

        // close trigger
        vm.warp(block.timestamp + 2 days);
        (need, data) = autoC.checkUpkeep("");
        assertTrue(need);
        autoC.performUpkeep(data);

        // register a prize so draw is needed (must be before finalize)
        MockERC20 tok = new MockERC20("TOK", "TOK");
        tok.mint(address(vault), 10);
        vm.startPrank(exe);
        lot.registerPrizeERC20(lot.currentRoundId(), address(tok), 10);
        vm.stopPrank();

        // finalize trigger
        (need, data) = autoC.checkUpkeep("");
        assertTrue(need);
        autoC.performUpkeep(data);

        // draw trigger
        (need, data) = autoC.checkUpkeep("");
        assertTrue(need);
        autoC.performUpkeep(data);

        // after purchase window end, start next
        vm.warp(block.timestamp + 2 days);
        (need, data) = autoC.checkUpkeep("");
        assertTrue(need);
        autoC.performUpkeep(data);

        // verify new round id started
        assertEq(lot.currentRoundId(), 2);
    }

    function test_Automation_DrawChunkPartial_And_SetChunk() public {
        // owner can set draw chunk
        vm.prank(owner);
        autoC.setDrawChunk(1);
        // not owner
        vm.expectRevert(LotteryAutomation.NotOwner.selector);
        autoC.setDrawChunk(2);

        // deposit and close
        vm.prank(user);
        lot.deposit{value: 0.05 ether}();
        vm.warp(block.timestamp + 2 days);
        (bool need, bytes memory data) = autoC.checkUpkeep("");
        autoC.performUpkeep(data); // close
        // register 2 prizes BEFORE finalize
        vm.startPrank(exe);
        MockERC20 t1 = new MockERC20("T1", "T1");
        t1.mint(address(vault), 10);
        lot.registerPrizeERC20(1, address(t1), 5);
        MockERC20 t2 = new MockERC20("T2", "T2");
        t2.mint(address(vault), 10);
        lot.registerPrizeERC20(1, address(t2), 5);
        vm.stopPrank();
        // finalize
        (need, data) = autoC.checkUpkeep("");
        autoC.performUpkeep(data);
        // draw chunk=1 will draw partially
        (need, data) = autoC.checkUpkeep("");
        autoC.performUpkeep(data);
        // second draw
        (need, data) = autoC.checkUpkeep("");
        autoC.performUpkeep(data);
    }
}
