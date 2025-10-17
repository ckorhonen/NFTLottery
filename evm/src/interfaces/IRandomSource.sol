// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRandomSource {
    // Request random words for a given round. Returns a request id if async, or 0 if sync.
    function requestRandom(uint256 roundId, uint32 numWords) external returns (uint256 requestId);

    // Read a random word for a round if available (either sync or fulfilled async).
    function getRandomWord(uint256 roundId, uint32 index) external view returns (uint256 word, bool available);
}

