// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRandomSource} from "../interfaces/IRandomSource.sol";

// Pseudo-randomness for tests/dev using block.prevrandao.
// Not suitable for mainnet fairness; replace with VRF adapter for production.
contract PseudoRandomSource is IRandomSource {
    event RandomRequested(uint256 indexed roundId, uint32 numWords);

    mapping(uint256 => uint256[]) private _roundWords;

    function requestRandom(uint256 roundId, uint32 numWords) external override returns (uint256) {
        delete _roundWords[roundId];
        uint256 seed =
            uint256(block.prevrandao) ^ uint256(blockhash(block.number - 1)) ^ (roundId << 128)
            ^ uint256(uint160(msg.sender));
        for (uint32 i = 0; i < numWords; i++) {
            // xorshift-like mixing
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            _roundWords[roundId].push(seed);
        }
        emit RandomRequested(roundId, numWords);
        return 0; // synchronous
    }

    function getRandomWord(uint256 roundId, uint32 index) external view override returns (uint256, bool) {
        if (index >= _roundWords[roundId].length) return (0, false);
        return (_roundWords[roundId][index], true);
    }
}

