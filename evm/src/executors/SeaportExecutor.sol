// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISeaport} from "./ISeaport.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IAssetAllowlist {
    function isCollectionAllowed(address token) external view returns (bool);
}

interface IPurchaseBudget {
    function consumePurchaseBudget(uint256 roundId, uint256 amount) external;
    function vaultAddress() external view returns (address);
}

interface ILotteryRegister {
    function registerPrizeERC721(uint256 roundId, address token, uint256 tokenId) external returns (uint256);
    function registerPrizeERC1155(uint256 roundId, address token, uint256 id, uint256 amount) external returns (uint256);
}

// Executes Seaport basic orders under strict constraints; trustless-ish.
contract SeaportExecutor is Ownable2Step, ReentrancyGuard, IERC721Receiver, IERC1155Receiver, ERC165 {
    ISeaport public immutable seaport;
    IAssetAllowlist public allowlist;
    IPurchaseBudget public budgeter;

    error CollectionNotAllowed();
    error InvalidRecipient();

    constructor(address seaport_, address owner_) Ownable(owner_) {
        seaport = ISeaport(seaport_);
    }

    function setAllowlist(address a) external onlyOwner {
        allowlist = IAssetAllowlist(a);
    }

    function setBudgeter(address b) external onlyOwner {
        budgeter = IPurchaseBudget(b);
    }

    // Executes a basic order paying native token. Ensures the NFT is delivered to the vault and collection is allowed.
    function buyBasicERC721(uint256 roundId, ISeaport.BasicOrderParameters calldata params)
        external
        payable
        nonReentrant
    {
        require(
            params.basicOrderType == ISeaport.ItemType.ERC721
                || params.basicOrderType == ISeaport.ItemType.ERC721_WITH_CRITERIA,
            "not ERC721"
        );
        if (!allowlist.isCollectionAllowed(params.offerToken)) revert CollectionNotAllowed();
        address vaultAddr = budgeter.vaultAddress();
        // Require an additional recipient is the vault for the NFT consideration? In basic, offer is NFT, consideration is payment recipients.
        // We can't assert NFT recipient here since Seaport transfers NFT directly from offerer to fulfiller (this contract) unless conduit used.
        // So require fulfiller conduit key is zero and we forward NFT to vault in a separate step OR specify recipient as vault via proxy pattern.
        // Simplify: this contract will be the fulfiller; NFT arrives here then immediately sent to vault after fulfillment.

        // Consume budget first to cap spend
        budgeter.consumePurchaseBudget(roundId, msg.value);

        bool ok = seaport.fulfillBasicOrder{value: msg.value}(params);
        require(ok, "seaport fail");

        // transfer the received NFT to the vault
        IERC721(params.offerToken).safeTransferFrom(address(this), vaultAddr, params.offerIdentifier);
        // register prize in the lottery (budgeter is the Lottery contract)
        ILotteryRegister(address(budgeter)).registerPrizeERC721(roundId, params.offerToken, params.offerIdentifier);
    }

    function buyBasicERC1155(uint256 roundId, ISeaport.BasicOrderParameters calldata params)
        external
        payable
        nonReentrant
    {
        require(
            params.basicOrderType == ISeaport.ItemType.ERC1155
                || params.basicOrderType == ISeaport.ItemType.ERC1155_WITH_CRITERIA,
            "not ERC1155"
        );
        if (!allowlist.isCollectionAllowed(params.offerToken)) revert CollectionNotAllowed();
        address vaultAddr = budgeter.vaultAddress();
        budgeter.consumePurchaseBudget(roundId, msg.value);
        bool ok = seaport.fulfillBasicOrder{value: msg.value}(params);
        require(ok, "seaport fail");
        // forward to vault and register
        IERC1155(params.offerToken)
            .safeTransferFrom(address(this), vaultAddr, params.offerIdentifier, params.offerAmount, "");
        ILotteryRegister(address(budgeter))
            .registerPrizeERC1155(roundId, params.offerToken, params.offerIdentifier, params.offerAmount);
    }

    // Receivers
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
