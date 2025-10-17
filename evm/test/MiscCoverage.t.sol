// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {SeaportExecutor} from "src/executors/SeaportExecutor.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract MiscCoverageTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address exe = address(0xE1);
    address user = address(0xBEEF);

    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
    PseudoRandomSource rnd;
    SeaportExecutor se;

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 1 days, 5000, 5000, 0, true, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        lot.setExecutor(exe, true);
        se = new SeaportExecutor(address(0x111122223333444455556666777788889999aAaa), owner);
        vm.stopPrank();
        vm.deal(user, 1 ether);
    }

    function test_Lottery_Setters_Views() public {
        vm.prank(owner);
        lot.setExecutor(address(0x1234), true);
        vm.prank(owner);
        lot.setSeaportExecutor(address(se), true);
        vm.prank(owner);
        lot.setUniswapV3Executor(address(0x5678), true);
        assertEq(lot.vaultAddress(), address(vault));
    }

    function test_PrizeVault_RecordERC20_Revert_Insufficient() public {
        // close round
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        // mint only 5 but try to record 10 (insufficient)
        MockERC20 t = new MockERC20("T", "T");
        t.mint(address(vault), 5);
        vm.prank(exe);
        vm.expectRevert(bytes("insufficient ERC20 in vault"));
        lot.registerPrizeERC20(1, address(t), 10);
    }

    function test_Seaport_SupportsInterface() public {
        assertTrue(se.supportsInterface(type(IERC721Receiver).interfaceId));
        assertTrue(se.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

    function test_PrizeVault_AmountUnclaimed_And_Interface() public {
        // close round & deposit
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        // mint ERC20 to vault and record as prize
        MockERC20 t = new MockERC20("T", "T");
        t.mint(address(vault), 20);
        vm.prank(exe);
        uint256 idx = lot.registerPrizeERC20(1, address(t), 20);
        // amountUnclaimed should be >= 20
        assertEq(vault.amountUnclaimed(address(t)), 20);
        // supportsInterface on vault
        bytes4 iid721 = type(IERC721Receiver).interfaceId;
        bytes4 iid1155 = type(IERC1155Receiver).interfaceId;
        // low-level call supportsInterface (since function is inherited)
        (bool ok, bytes memory data) =
            address(vault).staticcall(abi.encodeWithSignature("supportsInterface(bytes4)", iid721));
        require(ok);
        bool s1 = abi.decode(data, (bool));
        (ok, data) = address(vault).staticcall(abi.encodeWithSignature("supportsInterface(bytes4)", iid1155));
        require(ok);
        bool s2 = abi.decode(data, (bool));
        assertTrue(s1 && s2);
    }

    function test_Lottery_ClaimOwner_PerRound() public {
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        uint256 before = owner.balance;
        vm.prank(owner);
        lot.claimOwner(1);
        assertGt(owner.balance, before);
    }
}
