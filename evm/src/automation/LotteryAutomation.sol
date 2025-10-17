// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IKeeperCompatible {
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData);
    function performUpkeep(bytes calldata performData) external;
}

interface ILotteryView {
    function currentRoundId() external view returns (uint256);
    function rounds(uint256)
        external
        view
        returns (
            uint64 start,
            uint64 end,
            uint256 deposited,
            uint256 purchaseBudget,
            uint256 ownerAmount,
            bool closed,
            bool finalized,
            uint256 winnersDrawn
        );
    function purchaseWindow() external view returns (uint256);
    function finalizeRound(uint256 roundId) external;
    function closeRound() external;
    function drawWinners(uint256 roundId, uint256 maxToDraw) external;
    function startNextRound() external;
}

interface IPrizeVaultView {
    function roundPrizeCount(uint256 roundId) external view returns (uint256);
}

contract LotteryAutomation is IKeeperCompatible {
    ILotteryView public immutable lot;
    IPrizeVaultView public immutable vault;
    address public immutable owner;

    uint256 public drawChunk = 5;
    uint256 public lastClose;
    uint256 public lastFinalize;
    uint256 public lastDraw;
    uint256 public lastStart;

    event Performed(uint8 action, uint256 roundId, uint256 ts);

    error NotOwner();

    constructor(address lottery, address prizeVault, address owner_) {
        lot = ILotteryView(lottery);
        vault = IPrizeVaultView(prizeVault);
        owner = owner_;
    }

    function setDrawChunk(uint256 n) external {
        if (msg.sender != owner) revert NotOwner();
        require(n > 0 && n < 1000, "bad chunk");
        drawChunk = n;
    }

    function checkUpkeep(bytes calldata) external returns (bool upkeepNeeded, bytes memory performData) {
        (upkeepNeeded, performData) = _compute();
    }

    function performUpkeep(bytes calldata performData) external {
        (uint8 action, uint256 roundId, uint256 toDraw) = abi.decode(performData, (uint8, uint256, uint256));
        if (action == 1) {
            lot.closeRound();
            lastClose = block.timestamp;
            emit Performed(1, roundId, block.timestamp);
        } else if (action == 2) {
            lot.finalizeRound(roundId);
            lastFinalize = block.timestamp;
            emit Performed(2, roundId, block.timestamp);
        } else if (action == 3) {
            lot.drawWinners(roundId, toDraw);
            lastDraw = block.timestamp;
            emit Performed(3, roundId, block.timestamp);
        } else if (action == 4) {
            lot.startNextRound();
            lastStart = block.timestamp;
            emit Performed(4, roundId, block.timestamp);
        }
    }

    function _compute() internal view returns (bool upkeepNeeded, bytes memory performData) {
        uint256 rid = lot.currentRoundId();
        (uint64 start, uint64 end,,,, bool closed, bool finalized, uint256 winnersDrawn) = lot.rounds(rid);
        uint256 pw = lot.purchaseWindow();
        uint256 prizeCount = vault.roundPrizeCount(rid);
        if (!closed && block.timestamp >= end) return (true, abi.encode(uint8(1), rid, uint256(0)));
        if (closed && !finalized && block.timestamp >= end) return (true, abi.encode(uint8(2), rid, uint256(0)));
        if (finalized && winnersDrawn < prizeCount && prizeCount > 0) {
            uint256 remaining = prizeCount - winnersDrawn;
            uint256 toDraw = remaining > drawChunk ? drawChunk : remaining;
            return (true, abi.encode(uint8(3), rid, toDraw));
        }
        if (finalized && prizeCount == winnersDrawn && (block.timestamp >= end + pw)) {
            return (true, abi.encode(uint8(4), rid, uint256(0)));
        }
        return (false, bytes(""));
    }
}

