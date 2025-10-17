// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract LotteryTest is Test {
    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
    PseudoRandomSource rnd;

    address owner = address(0xA11CE);
    address feeRec = owner;
    address exe = address(0xE1);
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 3 days, 5000, 5000, 0, true, tix, vault, rnd);
        // wire permissions
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        lot.setExecutor(exe, true);
        vm.stopPrank();
    }

    function test_DepositCloseAndSplit() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        lot.deposit{value: 0.12 ether}(); // 12 tickets, refund dust

        (,, uint256 dep,,,,,) = lot.rounds(1);
        assertEq(dep, 0.12 ether);

        // advance time and close
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();

        (,,, uint256 purch, uint256 ownerAmt, bool closed,,) = lot.rounds(1);
        assertTrue(closed);
        assertEq(purch, 0.06 ether);
        assertEq(ownerAmt, 0.06 ether);

        // owner claim
        uint256 balBefore = owner.balance;
        vm.prank(owner);
        lot.claimOwner(1);
        assertEq(owner.balance, balBefore + 0.06 ether);
    }

    function test_RegisterPrizes_DrawAndClaim() public {
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.prank(user1);
        lot.deposit{value: 0.05 ether}(); // 5 tickets
        vm.prank(user2);
        lot.deposit{value: 0.07 ether}(); // 7 tickets

        vm.warp(block.timestamp + 2 days);
        lot.closeRound();

        // simulate executor registering ERC20 prize of 10 USDC (mock token addr)
        MockERC20 usdc = new MockERC20("USD Coin", "USDC");
        usdc.mint(address(vault), 10e6);
        vm.prank(exe);
        uint256 idx = lot.registerPrizeERC20(1, address(usdc), 10e6);
        assertEq(idx, 0);

        lot.finalizeRound(1);
        lot.drawWinners(1, 0);

        // winner set -> claim
        // prize 0 winner
        (,,,,,, address winner) = _prize(0);
        vm.prank(winner);
        vault.claim(0);
        assertEq(usdc.balanceOf(winner), 10e6);
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
