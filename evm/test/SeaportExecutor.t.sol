// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {SeaportExecutor} from "src/executors/SeaportExecutor.sol";
import {ISeaport} from "src/executors/ISeaport.sol";
import {CollectionAllowlist} from "src/Allowlists.sol";
import {MockERC721} from "test/mocks/MockERC721.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import {MockSeaport} from "test/mocks/MockSeaport.sol";

contract SeaportExecutorTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address user = address(0xBEEF);

    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
    PseudoRandomSource rnd;
    SeaportExecutor exec;
    CollectionAllowlist allow;
    MockSeaport seaport;

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 3 days, 5000, 5000, 0, false, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));

        seaport = new MockSeaport();
        exec = new SeaportExecutor(address(seaport), owner);
        allow = new CollectionAllowlist(owner);
        exec.setAllowlist(address(allow));
        exec.setBudgeter(address(lot));
        lot.setSeaportExecutor(address(exec), true);
        vm.stopPrank();

        vm.deal(user, 1 ether);
        vm.prank(user);
        lot.deposit{value: 0.05 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
    }

    function test_BasicERC721_ViaWrapper_RegistersPrize() public {
        MockERC721 col = new MockERC721("COL", "COL");
        // allowlist
        vm.prank(owner);
        allow.set(address(col), true);
        // mint NFT to executor so it can forward to vault after mock fulfill
        col.mint(address(exec), 1);

        ISeaport.BasicOrderParameters memory p = ISeaport.BasicOrderParameters({
            considerationToken: address(0),
            considerationIdentifier: 0,
            considerationAmount: 0.01 ether,
            offerer: payable(address(0x1)),
            zone: address(0),
            offerToken: address(col),
            offerIdentifier: 1,
            offerAmount: 1,
            basicOrderType: ISeaport.ItemType.ERC721,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            zoneHash: bytes32(0),
            salt: 1,
            offererConduitKey: bytes32(0),
            fulfillerConduitKey: bytes32(0),
            totalOriginalAdditionalRecipients: 0,
            additionalRecipients: new ISeaport.AdditionalRecipient[](0),
            signature: ""
        });

        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC721.selector, 1, p);
        vm.prank(address(exec));
        lot.executeSeaportBasicERC721(1, data, 0.01 ether, 0.02 ether);

        // verify vault owns the NFT and prize recorded
        assertEq(col.ownerOf(1), address(vault));
        assertEq(vault.roundPrizeCount(1), 1);
    }

    function test_BasicERC1155_ViaWrapper_RegistersPrize() public {
        MockERC1155 col = new MockERC1155();
        vm.prank(owner);
        allow.set(address(col), true);
        // mint to executor for forwarding
        col.mint(address(exec), 7, 5);

        ISeaport.BasicOrderParameters memory p = ISeaport.BasicOrderParameters({
            considerationToken: address(0),
            considerationIdentifier: 0,
            considerationAmount: 0.01 ether,
            offerer: payable(address(0x1)),
            zone: address(0),
            offerToken: address(col),
            offerIdentifier: 7,
            offerAmount: 5,
            basicOrderType: ISeaport.ItemType.ERC1155,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            zoneHash: bytes32(0),
            salt: 1,
            offererConduitKey: bytes32(0),
            fulfillerConduitKey: bytes32(0),
            totalOriginalAdditionalRecipients: 0,
            additionalRecipients: new ISeaport.AdditionalRecipient[](0),
            signature: ""
        });

        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC1155.selector, 1, p);
        vm.prank(address(exec));
        lot.executeSeaportBasicERC1155(1, data, 0.01 ether, 0.02 ether);
        assertEq(vault.roundPrizeCount(1), 1);
    }

    function test_BasicERC1155_WithCriteria_ViaWrapper() public {
        MockERC1155 col = new MockERC1155();
        vm.prank(owner);
        allow.set(address(col), true);
        col.mint(address(exec), 8, 2);
        ISeaport.BasicOrderParameters memory p = ISeaport.BasicOrderParameters({
            considerationToken: address(0),
            considerationIdentifier: 0,
            considerationAmount: 0.01 ether,
            offerer: payable(address(0x1)),
            zone: address(0),
            offerToken: address(col),
            offerIdentifier: 8,
            offerAmount: 2,
            basicOrderType: ISeaport.ItemType.ERC1155_WITH_CRITERIA,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            zoneHash: bytes32(0),
            salt: 1,
            offererConduitKey: bytes32(0),
            fulfillerConduitKey: bytes32(0),
            totalOriginalAdditionalRecipients: 0,
            additionalRecipients: new ISeaport.AdditionalRecipient[](0),
            signature: ""
        });
        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC1155.selector, 1, p);
        vm.prank(address(exec));
        lot.executeSeaportBasicERC1155(1, data, 0.01 ether, 0.02 ether);
        assertEq(vault.roundPrizeCount(1), 1);
    }

    function test_ERC1155_CollectionNotAllowed_Reverts() public {
        MockERC1155 col = new MockERC1155();
        col.mint(address(exec), 9, 2);
        ISeaport.BasicOrderParameters memory p = ISeaport.BasicOrderParameters({
            considerationToken: address(0),
            considerationIdentifier: 0,
            considerationAmount: 0.01 ether,
            offerer: payable(address(0x1)),
            zone: address(0),
            offerToken: address(col),
            offerIdentifier: 9,
            offerAmount: 2,
            basicOrderType: ISeaport.ItemType.ERC1155,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            zoneHash: bytes32(0),
            salt: 1,
            offererConduitKey: bytes32(0),
            fulfillerConduitKey: bytes32(0),
            totalOriginalAdditionalRecipients: 0,
            additionalRecipients: new ISeaport.AdditionalRecipient[](0),
            signature: ""
        });
        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC1155.selector, 1, p);
        vm.expectRevert(bytes("seaport exec fail"));
        vm.prank(address(exec));
        lot.executeSeaportBasicERC1155(1, data, 0.01 ether, 0.02 ether);
    }

    function test_ERC721_CollectionNotAllowed_Reverts() public {
        MockERC721 col = new MockERC721("COL", "COL");
        // not allowlisted
        col.mint(address(exec), 2);
        ISeaport.BasicOrderParameters memory p = ISeaport.BasicOrderParameters({
            considerationToken: address(0),
            considerationIdentifier: 0,
            considerationAmount: 0.01 ether,
            offerer: payable(address(0x1)),
            zone: address(0),
            offerToken: address(col),
            offerIdentifier: 2,
            offerAmount: 1,
            basicOrderType: ISeaport.ItemType.ERC721,
            startTime: block.timestamp,
            endTime: block.timestamp + 1 days,
            zoneHash: bytes32(0),
            salt: 1,
            offererConduitKey: bytes32(0),
            fulfillerConduitKey: bytes32(0),
            totalOriginalAdditionalRecipients: 0,
            additionalRecipients: new ISeaport.AdditionalRecipient[](0),
            signature: ""
        });
        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC721.selector, 1, p);
        vm.prank(owner);
        lot.setExecutor(owner, true);
        vm.expectRevert(bytes("seaport exec fail"));
        vm.prank(owner);
        lot.executeSeaportBasicERC721(1, data, 0.01 ether, 0.02 ether);
    }
}
