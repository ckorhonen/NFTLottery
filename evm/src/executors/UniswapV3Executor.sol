// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface ITokenAllowlist {
    function isTokenAllowed(address token) external view returns (bool);
}

interface IPurchaseBudget {
    function consumePurchaseBudget(uint256 roundId, uint256 amount) external;
    function vaultAddress() external view returns (address);
}

interface ILotteryRegister {
    function registerPrizeERC20(uint256 roundId, address token, uint256 amount) external returns (uint256);
}

contract UniswapV3Executor is Ownable2Step, ReentrancyGuard {
    ISwapRouter public immutable router;
    ITokenAllowlist public allowlist;
    IPurchaseBudget public budgeter;

    error TokenNotAllowed();

    constructor(address router_, address owner_) Ownable(owner_) {
        router = ISwapRouter(router_);
    }

    function setAllowlist(address a) external onlyOwner {
        allowlist = ITokenAllowlist(a);
    }

    function setBudgeter(address b) external onlyOwner {
        budgeter = IPurchaseBudget(b);
    }

    function swapExactInputSingle(uint256 roundId, ISwapRouter.ExactInputSingleParams calldata p)
        external
        payable
        nonReentrant
        returns (uint256 out)
    {
        if (!allowlist.isTokenAllowed(p.tokenOut)) revert TokenNotAllowed();
        address vaultAddr = budgeter.vaultAddress();
        require(p.recipient == vaultAddr, "recipient must be vault");
        // Trustless budget: require native in (Lottery provides msg.value)
        require(p.tokenIn == address(0), "native in only");
        require(p.amountIn == msg.value, "value mismatch");
        budgeter.consumePurchaseBudget(roundId, p.amountIn);
        out = router.exactInputSingle{value: p.amountIn}(p);
        ILotteryRegister(address(budgeter)).registerPrizeERC20(roundId, p.tokenOut, out);
    }
}
