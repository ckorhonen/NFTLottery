// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract LotteryEdgeTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address exe = address(0xE1);
    address u1 = address(0x1);
    address u2 = address(0x2);

    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
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

    function test_PauseBlocksDeposit() public {
        vm.prank(owner);
        lot.pause();
        vm.expectRevert();
        vm.prank(u1);
        lot.deposit{value: 0.01 ether}();
        vm.prank(owner);
        lot.unpause();
        vm.prank(u1);
        lot.deposit{value: 0.01 ether}();
    }

    function test_BudgetExceededAndWindowOver() public {
        // Round 1: budget exceeded
        vm.prank(u1);
        lot.deposit{value: 0.05 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        vm.prank(exe);
        lot.consumePurchaseBudget(1, (0.05 ether * 5000) / 10000);
        vm.prank(exe);
        vm.expectRevert(Lottery.BudgetExceeded.selector);
        lot.consumePurchaseBudget(1, 1);

        // Start next, then window over
        lot.finalizeRound(1);
        lot.startNextRound();
        vm.prank(u1);
        lot.deposit{value: 0.01 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        // move past window without consuming budget
        vm.warp(block.timestamp + 2 days);
        vm.prank(exe);
        vm.expectRevert(Lottery.PurchaseWindowOver.selector);
        lot.consumePurchaseBudget(2, 1);
    }

    function test_OneWinPerWallet() public {
        vm.prank(u1); // 5
        lot.deposit{value: 0.05 ether}();
        vm.prank(u2); // 5
        lot.deposit{value: 0.05 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        // register two ERC20 prizes
        MockERC20 tok = new MockERC20("TOK", "TOK");
        tok.mint(address(vault), 10);
        vm.prank(exe);
        lot.registerPrizeERC20(1, address(tok), 5);
        MockERC20 tok2 = new MockERC20("TOK2", "TOK2");
        tok2.mint(address(vault), 10);
        vm.prank(exe);
        lot.registerPrizeERC20(1, address(tok2), 5);
        lot.finalizeRound(1);
        lot.drawWinners(1, 0);
        // retrieve winners
        uint256 i0 = vault.prizeIndexAt(1, 0);
        uint256 i1 = vault.prizeIndexAt(1, 1);
        (,,,,,, address w0) = _prize(i0);
        (,,,,,, address w1) = _prize(i1);
        assertTrue(w0 != address(0) && w1 != address(0) && w0 != w1);
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
