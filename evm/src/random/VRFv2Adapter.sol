// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRandomSource} from "../interfaces/IRandomSource.sol";

// Minimal Chainlink VRF v2-compatible adapter (no external deps).
// Provide coordinator/keyHash/subId via constructor or setters.
interface IVRFCoordinatorV2 {
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);
}

contract VRFv2Adapter is IRandomSource {
    address public coordinator;
    bytes32 public keyHash;
    uint64 public subId;
    uint16 public minConfirmations;
    uint32 public callbackGasLimit;
    address public owner;

    mapping(uint256 => uint256[]) private _roundWords;
    mapping(uint256 => uint256) public requestToRound;

    event RandomRequested(uint256 indexed roundId, uint32 numWords, uint256 requestId);
    event Fulfilled(uint256 indexed roundId, uint256 indexed requestId, uint256 words);
    error NotOwner();
    error NotCoordinator();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address coord, bytes32 keyHash_, uint64 subId_, uint16 minConf, uint32 gasLimit, address owner_) {
        coordinator = coord;
        keyHash = keyHash_;
        subId = subId_;
        minConfirmations = minConf;
        callbackGasLimit = gasLimit;
        owner = owner_;
    }

    function setConfig(address coord, bytes32 keyHash_, uint64 subId_, uint16 minConf, uint32 gasLimit)
        external
        onlyOwner
    {
        coordinator = coord;
        keyHash = keyHash_;
        subId = subId_;
        minConfirmations = minConf;
        callbackGasLimit = gasLimit;
    }

    function requestRandom(uint256 roundId, uint32 numWords) external override returns (uint256 reqId) {
        reqId = IVRFCoordinatorV2(coordinator)
            .requestRandomWords(keyHash, subId, minConfirmations, callbackGasLimit, numWords);
        requestToRound[reqId] = roundId;
        emit RandomRequested(roundId, numWords, reqId);
    }

    // Called by the Chainlink VRF coordinator.
    function fulfillRandomWords(uint256 requestId, uint256[] memory words) external {
        if (msg.sender != coordinator) revert NotCoordinator();
        uint256 roundId = requestToRound[requestId];
        delete _roundWords[roundId];
        for (uint256 i = 0; i < words.length; i++) {
            _roundWords[roundId].push(words[i]);
        }
        emit Fulfilled(roundId, requestId, words.length);
    }

    function getRandomWord(uint256 roundId, uint32 index) external view override returns (uint256, bool) {
        if (index >= _roundWords[roundId].length) return (0, false);
        return (_roundWords[roundId][index], true);
    }
}

