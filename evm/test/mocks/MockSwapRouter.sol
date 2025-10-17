// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "src/executors/UniswapV3Executor.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract MockSwapRouter is ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        // Mint out tokens to the recipient equal to amountIn * 2 (arbitrary)
        amountOut = params.amountIn * 2;
        MockERC20(params.tokenOut).mint(params.recipient, amountOut);
    }
}

