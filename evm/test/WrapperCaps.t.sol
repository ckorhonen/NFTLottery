// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {SeaportExecutor} from "src/executors/SeaportExecutor.sol";
import {UniswapV3Executor, ISwapRouter} from "src/executors/UniswapV3Executor.sol";
import {ISeaport} from "src/executors/ISeaport.sol";

contract WrapperCapsTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address user = address(0xBEEF);

    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
    PseudoRandomSource rnd;
    SeaportExecutor se;
    UniswapV3Executor ue;

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 1 days, 5000, 5000, 0, true, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        se = new SeaportExecutor(address(0x111122223333444455556666777788889999aAaa), owner);
        ue = new UniswapV3Executor(address(0x111122223333444455556666777788889999AaaB), owner);
        lot.setSeaportExecutor(address(se), true);
        lot.setUniswapV3Executor(address(ue), true);
        vm.stopPrank();
        vm.deal(user, 1 ether);
    }

    function _basicOrder(address token, uint256 tokenId)
        internal
        view
        returns (ISeaport.BasicOrderParameters memory p)
    {
        p = ISeaport.BasicOrderParameters({
            considerationToken: address(0),
            considerationIdentifier: 0,
            considerationAmount: 0.02 ether,
            offerer: payable(address(0x1)),
            zone: address(0),
            offerToken: token,
            offerIdentifier: tokenId,
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
    }

    function test_Seaport_PriceCap_Revert() public {
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        ISeaport.BasicOrderParameters memory p = _basicOrder(address(0xCAFE), 1);
        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC721.selector, 1, p);
        vm.expectRevert(bytes("price>cap"));
        vm.prank(address(se));
        lot.executeSeaportBasicERC721(1, data, 0.02 ether, 0.01 ether);
    }

    function test_Uni_RoundIdMismatch_Revert() public {
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(0),
            tokenOut: address(0xCAFE),
            fee: 3000,
            recipient: address(vault),
            deadline: block.timestamp + 1 days,
            amountIn: 0.01 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        // encode with rid=99 but wrapper will be passed 1
        bytes memory data = abi.encodeWithSelector(UniswapV3Executor.swapExactInputSingle.selector, uint256(99), p);
        vm.expectRevert(bytes("rid mismatch"));
        vm.prank(address(ue));
        lot.executeUniV3SwapNative(1, data, p.amountIn, 0, p.amountIn);
    }

    function test_Uni_MinOutTooLow_Revert() public {
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(0),
            tokenOut: address(0xCAFE),
            fee: 3000,
            recipient: address(vault),
            deadline: block.timestamp + 1 days,
            amountIn: 0.01 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        bytes memory data = abi.encodeWithSelector(UniswapV3Executor.swapExactInputSingle.selector, uint256(1), p);
        vm.expectRevert(bytes("minOut too low"));
        vm.prank(address(ue));
        lot.executeUniV3SwapNative(1, data, p.amountIn, 1, p.amountIn);
    }
}
