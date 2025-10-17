// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PrizeVault is Ownable2Step, ReentrancyGuard, IERC721Receiver, IERC1155Receiver, ERC165 {
    using SafeERC20 for IERC20;
    address public controller; // Lottery contract

    enum PrizeType {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Prize {
        PrizeType pType;
        address asset;
        uint256 id; // tokenId for ERC721/1155
        uint256 amount; // amount for ERC20/1155
        uint256 roundId;
        bool claimed;
        address winner; // set by controller
    }

    Prize[] public prizes; // global index across rounds
    mapping(uint256 => uint256[]) public roundPrizes; // roundId => prize indices

    error NotController();
    error AlreadyClaimed();
    error NotWinner();

    event ControllerUpdated(address indexed controller);
    event PrizeRecorded(
        uint256 indexed prizeIndex, uint256 indexed roundId, PrizeType pType, address asset, uint256 id, uint256 amount
    );
    event PrizeWinnerSet(uint256 indexed prizeIndex, address indexed winner);
    event PrizeClaimed(uint256 indexed prizeIndex, address indexed winner);

    constructor(address owner_) Ownable(owner_) {}

    modifier onlyController() {
        if (msg.sender != controller) revert NotController();
        _;
    }

    function setController(address c) external onlyOwner {
        controller = c;
        emit ControllerUpdated(c);
    }

    // Record a prize after assets have been transferred to the vault.
    function recordERC721(uint256 roundId, address token, uint256 tokenId)
        external
        onlyController
        returns (uint256 idx)
    {
        require(IERC721(token).ownerOf(tokenId) == address(this), "NFT not in vault");
        idx = prizes.length;
        prizes.push(
            Prize({
                pType: PrizeType.ERC721,
                asset: token,
                id: tokenId,
                amount: 1,
                roundId: roundId,
                claimed: false,
                winner: address(0)
            })
        );
        roundPrizes[roundId].push(idx);
        emit PrizeRecorded(idx, roundId, PrizeType.ERC721, token, tokenId, 1);
    }

    function recordERC1155(uint256 roundId, address token, uint256 id, uint256 amount)
        external
        onlyController
        returns (uint256 idx)
    {
        idx = prizes.length;
        prizes.push(
            Prize({
                pType: PrizeType.ERC1155,
                asset: token,
                id: id,
                amount: amount,
                roundId: roundId,
                claimed: false,
                winner: address(0)
            })
        );
        roundPrizes[roundId].push(idx);
        emit PrizeRecorded(idx, roundId, PrizeType.ERC1155, token, id, amount);
    }

    function recordERC20(uint256 roundId, address token, uint256 amount) external onlyController returns (uint256 idx) {
        require(
            IERC20(token).balanceOf(address(this)) >= amountUnclaimed(token) + amount, "insufficient ERC20 in vault"
        );
        idx = prizes.length;
        prizes.push(
            Prize({
                pType: PrizeType.ERC20,
                asset: token,
                id: 0,
                amount: amount,
                roundId: roundId,
                claimed: false,
                winner: address(0)
            })
        );
        roundPrizes[roundId].push(idx);
        emit PrizeRecorded(idx, roundId, PrizeType.ERC20, token, 0, amount);
    }

    function amountUnclaimed(address token) public view returns (uint256 sum) {
        for (uint256 i = 0; i < prizes.length; i++) {
            Prize storage p = prizes[i];
            if (!p.claimed && p.pType == PrizeType.ERC20 && p.asset == token) sum += p.amount;
        }
    }

    function setPrizeWinner(uint256 prizeIndex, address winner) external onlyController {
        Prize storage p = prizes[prizeIndex];
        require(!p.claimed, "claimed");
        p.winner = winner;
        emit PrizeWinnerSet(prizeIndex, winner);
    }

    function roundPrizeCount(uint256 roundId) external view returns (uint256) {
        return roundPrizes[roundId].length;
    }

    function prizeIndexAt(uint256 roundId, uint256 i) external view returns (uint256) {
        return roundPrizes[roundId][i];
    }

    function prizesLength() external view returns (uint256) {
        return prizes.length;
    }

    function claim(uint256 prizeIndex) external nonReentrant {
        Prize storage p = prizes[prizeIndex];
        if (p.claimed) revert AlreadyClaimed();
        if (p.winner != msg.sender) revert NotWinner();
        p.claimed = true;
        if (p.pType == PrizeType.ERC721) {
            IERC721(p.asset).transferFrom(address(this), msg.sender, p.id);
        } else if (p.pType == PrizeType.ERC1155) {
            IERC1155(p.asset).safeTransferFrom(address(this), msg.sender, p.id, p.amount, "");
        } else {
            IERC20(p.asset).safeTransfer(msg.sender, p.amount);
        }
        emit PrizeClaimed(prizeIndex, msg.sender);
    }

    // Receivers for safeTransferFrom
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 iid) public view virtual override(ERC165, IERC165) returns (bool) {
        return iid == type(IERC721Receiver).interfaceId || iid == type(IERC1155Receiver).interfaceId
            || super.supportsInterface(iid);
    }
}
