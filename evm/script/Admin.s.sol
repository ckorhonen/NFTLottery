// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Lottery} from "src/Lottery.sol";

contract Admin is Script {
    function finalize(uint256 roundId, address payable lottery) external {
        vm.startBroadcast();
        Lottery(lottery).finalizeRound(roundId);
        vm.stopBroadcast();
    }

    function draw(uint256 roundId, uint256 maxToDraw, address payable lottery) external {
        vm.startBroadcast();
        Lottery(lottery).drawWinners(roundId, maxToDraw);
        vm.stopBroadcast();
    }

    function next(address payable lottery) external {
        vm.startBroadcast();
        Lottery(lottery).startNextRound();
        vm.stopBroadcast();
    }
}
