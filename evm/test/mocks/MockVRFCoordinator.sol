// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRFCoordinatorV2} from "src/random/VRFv2Adapter.sol";

contract MockVRFCoordinator is IVRFCoordinatorV2 {
    uint256 public lastRequestId;

    function requestRandomWords(bytes32, uint64, uint16, uint32, uint32) external override returns (uint256 requestId) {
        lastRequestId += 1;
        return lastRequestId;
    }
}

