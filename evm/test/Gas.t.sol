// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Lottery} from "src/Lottery.sol";
import {Ticket1155} from "src/Ticket1155.sol";
import {PrizeVault} from "src/PrizeVault.sol";
import {PseudoRandomSource} from "src/random/PseudoRandomSource.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {UniswapV3Executor, ISwapRouter} from "src/executors/UniswapV3Executor.sol";
import {TokenAllowlist} from "src/Allowlists.sol";
import {MockSwapRouter} from "test/mocks/MockSwapRouter.sol";

contract GasTest is Test {
    Lottery lot;
    Ticket1155 tix;
    PrizeVault vault;
    PseudoRandomSource rnd;
    address owner = address(0xA11CE);
    address feeRec = owner;
    address exe = address(0xE1);
    address user = address(0xBEEF);

    function setUp() public {
        vm.startPrank(owner);
        tix = new Ticket1155("ipfs://template/{id}.json", owner);
        vault = new PrizeVault(owner);
        rnd = new PseudoRandomSource();
        lot = new Lottery(
            owner,
            feeRec,
            0.01 ether,
            1 days,
            3 days,
            5000,
            5000,
            0,
            false, // enforce one-win-per-wallet in gas tests
            tix,
            vault,
            rnd
        );
        vault.setController(address(lot));
        tix.setMinter(address(lot));
        lot.setExecutor(exe, true);
        vm.stopPrank();
        vm.deal(user, 10 ether);
    }

    function testGas_DepositSingle() public {
        vm.prank(user);
        lot.deposit{value: 0.01 ether}();
    }

    function testGas_CloseRound_Finalize_Draw_Claim() public {
        // setup: deposits
        vm.prank(user);
        lot.deposit{value: 0.05 ether}();
        // close round after duration
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();

        // register a small ERC20 prize via executor role
        MockERC20 usdc = new MockERC20("USD Coin", "USDC");
        usdc.mint(address(vault), 10e6);
        vm.prank(exe);
        lot.registerPrizeERC20(1, address(usdc), 10e6);

        // finalize
        lot.finalizeRound(1);
        // draw all winners
        lot.drawWinners(1, 0);

        // claim prize
        (,,,,,, address winner) = _prize(0);
        vm.prank(winner);
        vault.claim(0);
    }

    function testGas_SwapNative_RegistersPrize() public {
        // Setup router + executor
        MockSwapRouter router = new MockSwapRouter();
        vm.startPrank(owner);
        UniswapV3Executor ue = new UniswapV3Executor(address(router), owner);
        ue.setBudgeter(address(lot));
        lot.setUniswapV3Executor(address(ue), true);
        vm.stopPrank();

        // Allowed token and deposit
        MockERC20 out = new MockERC20("OUT", "OUT");
        vm.startPrank(owner);
        // set token allowlist
        // Reuse simple allowlist from Allowlists
        // Deploy a minimal allowlist and set token
        address allow = address(new TokenAllowlist(owner));
        TokenAllowlist(allow).set(address(out), true);
        ue.setAllowlist(allow);
        vm.stopPrank();

        vm.prank(user);
        lot.deposit{value: 0.05 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();

        // Build swap params
        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(0),
            tokenOut: address(out),
            fee: 3000,
            recipient: address(lot.vault()),
            deadline: block.timestamp + 1 days,
            amountIn: 0.01 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // Encode call to executor via Lottery wrapper
        bytes memory callData = abi.encodeWithSelector(UniswapV3Executor.swapExactInputSingle.selector, 1, p);
        vm.prank(address(ue));
        lot.executeUniV3SwapNative(1, callData, p.amountIn, 0, p.amountIn);

        // Prize should be registered; draw and claim
        lot.finalizeRound(1);
        lot.drawWinners(1, 0);
        (,,,,,, address winner) = _prize(0);
        vm.prank(winner);
        vault.claim(0);
        assertGt(out.balanceOf(winner), 0);
    }

    function test_UniV3_WrongRecipient_Reverts() public {
        MockSwapRouter router = new MockSwapRouter();
        vm.startPrank(owner);
        UniswapV3Executor ue = new UniswapV3Executor(address(router), owner);
        ue.setBudgeter(address(lot));
        address allow = address(new TokenAllowlist(owner));
        TokenAllowlist(allow).set(address(0xCAFE), true); // dummy, not used
        ue.setAllowlist(allow);
        lot.setUniswapV3Executor(address(ue), true);
        vm.stopPrank();

        vm.prank(user);
        lot.deposit{value: 0.02 ether}();
        vm.warp(block.timestamp + 2 days);
        lot.closeRound();

        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(0),
            tokenOut: address(0xCAFE),
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 1 days,
            amountIn: 0.005 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        bytes memory data = abi.encodeWithSelector(UniswapV3Executor.swapExactInputSingle.selector, 1, p);
        vm.expectRevert(bytes("uniswap exec fail"));
        vm.prank(address(ue));
        lot.executeUniV3SwapNative(1, data, p.amountIn, 0, p.amountIn);
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
