// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {MockERC721} from "test/mocks/MockERC721.sol";

contract PrizeVaultERC721Test is Test {
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
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 1 days, 5000, 5000, 0, true, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        lot.setExecutor(exe, true);
        vm.stopPrank();
        vm.deal(u1, 1 ether);
    }

    function test_ClaimERC721() public {
        MockERC721 col = new MockERC721("COL", "COL");
        // close round first
        vm.prank(u1);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        // transfer NFT into vault and record prize
        col.mint(address(this), 11);
        col.transferFrom(address(this), address(vault), 11);
        vm.prank(exe);
        uint256 idx = lot.registerPrizeERC721(1, address(col), 11);
        lot.finalizeRound(1);
        lot.drawWinners(1, 0);
        (,,,,,, address winner) = _prize(idx);
        vm.prank(winner);
        vault.claim(idx);
        assertEq(col.ownerOf(11), winner);
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
