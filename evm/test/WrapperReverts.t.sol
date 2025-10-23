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
import {CollectionAllowlist, TokenAllowlist} from "src/Allowlists.sol";
import {MockSeaport} from "test/mocks/MockSeaport.sol";
import {MockSwapRouter} from "test/mocks/MockSwapRouter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract WrapperRevertsTest is Test {
    address owner = address(0xA11CE);
    address feeRec = owner;
    address user = address(0xBEEF);

    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
    PseudoRandomSource rnd;
    SeaportExecutor se;
    CollectionAllowlist collAllow;
    UniswapV3Executor ue;
    TokenAllowlist tokAllow;
    MockSeaport sea;
    MockSwapRouter router;

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        lot = new Lottery(owner, feeRec, 0.01 ether, 1 days, 1 days, 5000, 5000, 0, false, tix, vault, rnd);
        vault.setController(address(lot));
        tix.setMinter(address(lot));

        sea = new MockSeaport();
        se = new SeaportExecutor(address(sea), owner);
        collAllow = new CollectionAllowlist(owner);
        se.setAllowlist(address(collAllow));
        se.setBudgeter(address(lot));
        lot.setSeaportExecutor(address(se), true);

        router = new MockSwapRouter();
        ue = new UniswapV3Executor(address(router), owner);
        tokAllow = new TokenAllowlist(owner);
        ue.setAllowlist(address(tokAllow));
        ue.setBudgeter(address(lot));
        lot.setUniswapV3Executor(address(ue), true);
        vm.stopPrank();

        vm.deal(user, 1 ether);
    }

    function _basicOrder(address token, uint256 tokenId, uint8 itemType, uint256 amount)
        internal
        view
        returns (ISeaport.BasicOrderParameters memory p)
    {
        p = ISeaport.BasicOrderParameters({
            considerationToken: address(0),
            considerationIdentifier: 0,
            considerationAmount: 0.01 ether,
            offerer: payable(address(0x1)),
            zone: address(0),
            offerToken: token,
            offerIdentifier: tokenId,
            offerAmount: amount,
            basicOrderType: ISeaport.ItemType(itemType),
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

    function test_Seaport_NotSet_Reverts() public {
        // unset executor
        vm.prank(owner);
        lot.setSeaportExecutor(address(0), false);
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        ISeaport.BasicOrderParameters memory p = _basicOrder(address(0xCAFE), 1, uint8(ISeaport.ItemType.ERC721), 1);
        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC721.selector, 1, p);
        vm.prank(owner);
        lot.setExecutor(owner, true);
        vm.expectRevert(bytes("exec not set"));
        vm.prank(owner);
        lot.executeSeaportBasicERC721(1, data, 0.01 ether, 0.02 ether);
    }

    function test_Seaport_BadState_Reverts() public {
        // before close
        ISeaport.BasicOrderParameters memory p = _basicOrder(address(0xCAFE), 1, uint8(ISeaport.ItemType.ERC721), 1);
        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC721.selector, 1, p);
        vm.prank(owner);
        lot.setExecutor(owner, true);
        vm.expectRevert(bytes("bad state"));
        vm.prank(owner);
        lot.executeSeaportBasicERC721(1, data, 0.01 ether, 0.02 ether);
    }

    function test_Seaport_WindowExpired_Reverts() public {
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        // wait beyond purchase window
        vm.warp(block.timestamp + 2 days);
        ISeaport.BasicOrderParameters memory p = _basicOrder(address(0xCAFE), 1, uint8(ISeaport.ItemType.ERC721), 1);
        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC721.selector, 1, p);
        vm.expectRevert(bytes("seaport exec fail"));
        vm.prank(address(se));
        lot.executeSeaportBasicERC721(1, data, 0.01 ether, 0.02 ether);
    }

    function test_Seaport_BudgetExceeded_Reverts() public {
        vm.prank(user); // budget = 0.01
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        ISeaport.BasicOrderParameters memory p = _basicOrder(address(0xCAFE), 1, uint8(ISeaport.ItemType.ERC721), 1);
        bytes memory data = abi.encodeWithSelector(SeaportExecutor.buyBasicERC721.selector, 1, p);
        vm.expectRevert(bytes("seaport exec fail"));
        vm.prank(address(se));
        lot.executeSeaportBasicERC721(1, data, 0.02 ether, 0.02 ether);
    }

    function test_Uni_NotSet_Reverts() public {
        vm.prank(owner);
        lot.setUniswapV3Executor(address(0), false);
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
            amountIn: 0.005 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        bytes memory data = abi.encodeWithSelector(UniswapV3Executor.swapExactInputSingle.selector, 1, p);
        vm.prank(owner);
        lot.setExecutor(owner, true);
        vm.expectRevert(bytes("exec not set"));
        vm.prank(owner);
        lot.executeUniV3SwapNative(1, data, p.amountIn, 0, p.amountIn);
    }

    function test_Uni_BadState_Reverts() public {
        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(0),
            tokenOut: address(0xCAFE),
            fee: 3000,
            recipient: address(vault),
            deadline: block.timestamp + 1 days,
            amountIn: 0.005 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        bytes memory data = abi.encodeWithSelector(UniswapV3Executor.swapExactInputSingle.selector, 1, p);
        vm.prank(owner);
        lot.setExecutor(owner, true);
        vm.expectRevert(bytes("bad state"));
        vm.prank(owner);
        lot.executeUniV3SwapNative(1, data, p.amountIn, 0, p.amountIn);
    }

    function test_Uni_WindowExpired_Reverts() public {
        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();
        vm.warp(block.timestamp + 2 days);
        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(0),
            tokenOut: address(0xCAFE),
            fee: 3000,
            recipient: address(vault),
            deadline: block.timestamp + 1 days,
            amountIn: 0.02 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        bytes memory data = abi.encodeWithSelector(UniswapV3Executor.swapExactInputSingle.selector, 1, p);
        vm.expectRevert(bytes("uniswap exec fail"));
        vm.prank(address(ue));
        lot.executeUniV3SwapNative(1, data, p.amountIn, 0, p.amountIn);
    }

    function test_Uni_BudgetExceeded_Reverts() public {
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
            amountIn: 0.02 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        bytes memory data = abi.encodeWithSelector(UniswapV3Executor.swapExactInputSingle.selector, 1, p);
        vm.expectRevert(bytes("uniswap exec fail"));
        vm.prank(address(ue));
        lot.executeUniV3SwapNative(1, data, p.amountIn, 0, p.amountIn);
    }
}
