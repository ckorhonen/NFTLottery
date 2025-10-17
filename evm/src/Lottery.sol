// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Ticket1155} from "./Ticket1155.sol";
import {PrizeVault} from "./PrizeVault.sol";
import {IRandomSource} from "./interfaces/IRandomSource.sol";

contract Lottery is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeCast for uint256;

    // Fees are in basis points (10000 = 100%)
    uint256 public immutable purchaseShareBps; // portion of round funds used to buy prizes
    uint256 public immutable ownerShareBps; // portion allocated to owner
    uint256 public immutable ticketPrice; // in native token
    uint256 public immutable roundDuration; // seconds
    uint256 public immutable purchaseWindow; // seconds after close to allow purchases
    uint256 public immutable thresholdCap; // if > 0, auto-close when total >= cap
    bool public immutable allowMultipleWins;

    Ticket1155 public immutable tickets;
    PrizeVault public immutable vault;
    IRandomSource public random;

    address public immutable feeRecipient; // owner share recipient (owner by default)

    // round state
    struct Round {
        uint64 start;
        uint64 end;
        uint256 deposited;
        uint256 purchaseBudget;
        uint256 ownerAmount;
        bool closed;
        bool finalized;
        uint256 winnersDrawn; // number of prizes distributed
    }

    uint256 public currentRoundId;
    mapping(uint256 => Round) public rounds;

    // per round accounting
    mapping(uint256 => mapping(address => uint256)) public ticketsOf; // roundId => addr => ticket count
    mapping(uint256 => address[]) public participants; // roundId => list of participants
    mapping(uint256 => bool) private _isParticipant; // reused via salt key in mapping? We'll use keccak with roundId; simplified via helper

    // budgets consumption tracking
    mapping(uint256 => uint256) public purchaseSpent; // roundId => spent in native currency

    // executors authorized to register prizes and spend budget via consumePurchaseBudget
    mapping(address => bool) public isExecutor;

    // winner uniqueness tracking when allowMultipleWins == false
    mapping(uint256 => mapping(address => bool)) public hasWon;

    // aggregated owner accrual across rounds for gas-efficient withdrawals
    uint256 public ownerAccrued;

    // Optional executors for on-budget purchases
    address public seaportExecutor;
    address public uniswapV3Executor;

    event Deposit(address indexed user, uint256 indexed roundId, uint256 tickets, uint256 value);
    event RoundClosed(uint256 indexed roundId, uint256 deposited, uint256 purchaseBudget, uint256 ownerAmount);
    event PrizeRegistered(uint256 indexed roundId, uint256 prizeIndex);
    event RoundFinalized(uint256 indexed roundId, uint256 prizeCount);
    event WinnerDrawn(uint256 indexed roundId, uint256 prizeIndex, address winner);
    event ExecutorSet(address indexed executor, bool allowed);

    error RoundActive();
    error RoundClosedErr();
    error NotExecutor();
    error PurchaseWindowOver();
    error BudgetExceeded();

    modifier onlyExecutor() {
        if (!isExecutor[msg.sender]) revert NotExecutor();
        _;
    }

    constructor(
        address owner_,
        address feeRecipient_,
        uint256 ticketPrice_,
        uint256 roundDuration_,
        uint256 purchaseWindow_,
        uint256 purchaseShareBps_,
        uint256 ownerShareBps_,
        uint256 thresholdCap_,
        bool allowMultipleWins_,
        Ticket1155 tickets_,
        PrizeVault vault_,
        IRandomSource random_
    ) Ownable(owner_) {
        require(purchaseShareBps_ + ownerShareBps_ == 10000, "splits != 100%");
        feeRecipient = feeRecipient_ == address(0) ? owner_ : feeRecipient_;
        ticketPrice = ticketPrice_;
        roundDuration = roundDuration_;
        purchaseWindow = purchaseWindow_;
        purchaseShareBps = purchaseShareBps_;
        ownerShareBps = ownerShareBps_;
        thresholdCap = thresholdCap_;
        allowMultipleWins = allowMultipleWins_;
        tickets = tickets_;
        vault = vault_;
        random = random_;

        // start first round
        currentRoundId = 1;
        rounds[1] = Round({
            start: uint64(block.timestamp),
            end: uint64(block.timestamp + roundDuration_),
            deposited: 0,
            purchaseBudget: 0,
            ownerAmount: 0,
            closed: false,
            finalized: false,
            winnersDrawn: 0
        });
    }

    receive() external payable {}

    function setExecutor(address exec, bool allowed) external onlyOwner {
        isExecutor[exec] = allowed;
        emit ExecutorSet(exec, allowed);
    }

    function setSeaportExecutor(address exec, bool allowed) external onlyOwner {
        seaportExecutor = exec;
        isExecutor[exec] = allowed;
        emit ExecutorSet(exec, allowed);
    }

    function setUniswapV3Executor(address exec, bool allowed) external onlyOwner {
        uniswapV3Executor = exec;
        isExecutor[exec] = allowed;
        emit ExecutorSet(exec, allowed);
    }

    function deposit() external payable whenNotPaused nonReentrant {
        Round storage r = rounds[currentRoundId];
        if (block.timestamp > r.end || r.closed) revert RoundClosedErr();
        require(msg.value >= ticketPrice, "amount < price");
        uint256 t = msg.value / ticketPrice;
        uint256 valueUsed = t * ticketPrice;
        if (t == 0) revert();
        if (ticketsOf[currentRoundId][msg.sender] == 0) participants[currentRoundId].push(msg.sender);
        ticketsOf[currentRoundId][msg.sender] += t;
        r.deposited += valueUsed;
        tickets.mint(msg.sender, currentRoundId, t);
        emit Deposit(msg.sender, currentRoundId, t, valueUsed);

        // refund dust
        uint256 refund = msg.value - valueUsed;
        if (refund > 0) payable(msg.sender).transfer(refund);

        if (thresholdCap > 0 && r.deposited >= thresholdCap) {
            _closeRound();
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function closeRound() external whenNotPaused {
        _closeRound();
    }

    function _closeRound() internal {
        Round storage r = rounds[currentRoundId];
        if (r.closed) revert RoundClosedErr();
        if (block.timestamp < r.end && !(thresholdCap > 0 && r.deposited >= thresholdCap)) revert RoundActive();
        r.closed = true;
        r.purchaseBudget = (r.deposited * purchaseShareBps) / 10000;
        r.ownerAmount = r.deposited - r.purchaseBudget; // remainder
        ownerAccrued += r.ownerAmount; // accrue globally for cheaper owner withdrawals
        emit RoundClosed(currentRoundId, r.deposited, r.purchaseBudget, r.ownerAmount);
        // request randomness for this round upfront (numWords placeholder 4)
        random.requestRandom(currentRoundId, 4);
    }

    // Executors call before purchase to enforce budgets. Can be batched across buys.
    function consumePurchaseBudget(uint256 roundId, uint256 amount) external onlyExecutor {
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "not purch phase");
        if (block.timestamp > r.end + purchaseWindow) revert PurchaseWindowOver();
        purchaseSpent[roundId] += amount;
        if (purchaseSpent[roundId] > r.purchaseBudget) revert BudgetExceeded();
    }

    function vaultAddress() external view returns (address) {
        return address(vault);
    }

    // Registration APIs (only executors)
    function registerPrizeERC721(uint256 roundId, address token, uint256 tokenId)
        external
        onlyExecutor
        returns (uint256 prizeIndex)
    {
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "not purch phase");
        prizeIndex = vault.recordERC721(roundId, token, tokenId);
        emit PrizeRegistered(roundId, prizeIndex);
    }

    function registerPrizeERC1155(uint256 roundId, address token, uint256 id, uint256 amount)
        external
        onlyExecutor
        returns (uint256 prizeIndex)
    {
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "not purch phase");
        prizeIndex = vault.recordERC1155(roundId, token, id, amount);
        emit PrizeRegistered(roundId, prizeIndex);
    }

    function registerPrizeERC20(uint256 roundId, address token, uint256 amount)
        external
        onlyExecutor
        returns (uint256 prizeIndex)
    {
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "not purch phase");
        prizeIndex = vault.recordERC20(roundId, token, amount);
        emit PrizeRegistered(roundId, prizeIndex);
    }

    function finalizeRound(uint256 roundId) external {
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "bad state");
        require(block.timestamp >= r.end, "before end");
        // allow finalize even if purchase window not expired (manual)
        r.finalized = true;
        emit RoundFinalized(roundId, vault.roundPrizeCount(roundId));
    }

    // Draw winners and assign prizes. Anyone can call once finalized.
    function drawWinners(uint256 roundId, uint256 maxToDraw) external {
        Round storage r = rounds[roundId];
        require(r.finalized, "not finalized");
        uint256 prizeCount = vault.roundPrizeCount(roundId);
        uint256 toDraw = maxToDraw == 0 ? prizeCount - r.winnersDrawn : maxToDraw;
        require(toDraw > 0, "nothing to draw");

        // build local copy of participants to iterate
        address[] storage addrs = participants[roundId];
        uint256 totalTickets = r.deposited / ticketPrice;

        for (uint256 i = 0; i < toDraw; i++) {
            (uint256 word, bool ok) = random.getRandomWord(roundId, uint32(r.winnersDrawn + i));
            uint256 rnd =
                ok ? word : uint256(keccak256(abi.encodePacked(block.prevrandao, roundId, r.winnersDrawn + i)));
            address winner = _pickWeightedWinner(roundId, rnd, totalTickets, addrs);

            if (!allowMultipleWins && addrs.length > 0) {
                // ensure uniqueness where possible
                uint256 attempts = 0;
                uint256 maxAttempts = addrs.length * 2; // bounded
                while (hasWon[roundId][winner] && attempts < maxAttempts) {
                    rnd = uint256(keccak256(abi.encodePacked(rnd, attempts, block.prevrandao)));
                    winner = _pickWeightedWinner(roundId, rnd, totalTickets, addrs);
                    attempts++;
                }
            }

            uint256 prizeIndex = vault.prizeIndexAt(roundId, r.winnersDrawn + i);
            vault.setPrizeWinner(prizeIndex, winner);
            if (!allowMultipleWins && winner != address(0)) hasWon[roundId][winner] = true;
            emit WinnerDrawn(roundId, prizeIndex, winner);
        }
        r.winnersDrawn += toDraw;
    }

    function _pickWeightedWinner(uint256 roundId, uint256 rnd, uint256 totalTickets, address[] storage addrs)
        internal
        view
        returns (address winner)
    {
        if (addrs.length == 0 || totalTickets == 0) return address(0);
        uint256 pick = rnd % totalTickets;
        uint256 acc = 0;
        for (uint256 j = 0; j < addrs.length; j++) {
            acc += ticketsOf[roundId][addrs[j]];
            if (pick < acc) return addrs[j];
        }
        return addrs[0];
    }

    // Start next round once current is finalized.
    function startNextRound() external {
        Round storage r = rounds[currentRoundId];
        require(r.finalized, "current not finalized");
        currentRoundId += 1;
        rounds[currentRoundId] = Round({
            start: uint64(block.timestamp),
            end: uint64(block.timestamp + roundDuration),
            deposited: 0,
            purchaseBudget: 0,
            ownerAmount: 0,
            closed: false,
            finalized: false,
            winnersDrawn: 0
        });
    }

    // Owner claims their share (in native token) for a specific round.
    function claimOwner(uint256 roundId) external nonReentrant {
        require(msg.sender == feeRecipient, "not feeRecipient");
        Round storage r = rounds[roundId];
        require(r.closed, "not closed");
        uint256 amt = r.ownerAmount;
        r.ownerAmount = 0;
        if (ownerAccrued >= amt) ownerAccrued -= amt;
        (bool s,) = payable(feeRecipient).call{value: amt}("");
        require(s, "transfer failed");
    }

    // Owner claims all accrued funds across rounds.
    function claimOwnerAll() external nonReentrant {
        require(msg.sender == feeRecipient, "not feeRecipient");
        uint256 amt = ownerAccrued;
        ownerAccrued = 0;
        (bool s,) = payable(feeRecipient).call{value: amt}("");
        require(s, "transfer failed");
    }

    // -------- Purchase wrappers (spend budget from this contract) --------
    function executeSeaportBasicERC721(
        uint256 roundId,
        bytes calldata seaportCallData,
        uint256 nativePrice,
        uint256 maxNativeSpend
    ) external onlyExecutor {
        require(isExecutor[seaportExecutor], "exec not set");
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "bad state");
        require(nativePrice <= maxNativeSpend, "price>cap");
        // value is enforced by executor/budgeter.consumePurchaseBudget; mirror here for clarity
        (bool ok,) = seaportExecutor.call{value: nativePrice}(seaportCallData);
        require(ok, "seaport exec fail");
    }

    function executeSeaportBasicERC1155(
        uint256 roundId,
        bytes calldata seaportCallData,
        uint256 nativePrice,
        uint256 maxNativeSpend
    ) external onlyExecutor {
        require(isExecutor[seaportExecutor], "exec not set");
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "bad state");
        require(nativePrice <= maxNativeSpend, "price>cap");
        (bool ok,) = seaportExecutor.call{value: nativePrice}(seaportCallData);
        require(ok, "seaport exec fail");
    }

    struct ExactInputSingleParamsLocal {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function executeUniV3SwapNative(
        uint256 roundId,
        bytes calldata routerCallData,
        uint256 nativeIn,
        uint256 minOut,
        uint256 maxNativeSpend
    ) external onlyExecutor {
        require(isExecutor[uniswapV3Executor], "exec not set");
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "bad state");
        require(nativeIn <= maxNativeSpend, "price>cap");
        // decode to assert minOut
        bytes4 sel;
        assembly { sel := calldataload(routerCallData.offset) }
        // skip selector
        (uint256 decodedRid, ExactInputSingleParamsLocal memory p) =
            abi.decode(routerCallData[4:], (uint256, ExactInputSingleParamsLocal));
        require(decodedRid == roundId, "rid mismatch");
        require(p.amountOutMinimum >= minOut, "minOut too low");
        (bool ok,) = uniswapV3Executor.call{value: nativeIn}(routerCallData);
        require(ok, "uniswap exec fail");
    }

    // Split ERC20 prizes into denominations; only during purchase phase
    function bundleERC20Prizes(uint256 roundId, address token, uint256 unitAmount, uint256 count)
        external
        onlyExecutor
    {
        Round storage r = rounds[roundId];
        require(r.closed && !r.finalized, "bad state");
        require(unitAmount > 0 && count > 0, "bad params");
        for (uint256 i = 0; i < count; i++) {
            uint256 idx = vault.recordERC20(roundId, token, unitAmount);
            emit PrizeRegistered(roundId, idx);
        }
    }
}
