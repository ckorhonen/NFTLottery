// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Minimal Seaport interface for basic orders.
interface ISeaport {
    enum ItemType {
        NATIVE,
        ERC20,
        ERC721,
        ERC1155,
        ERC721_WITH_CRITERIA,
        ERC1155_WITH_CRITERIA
    }

    struct AdditionalRecipient {
        uint256 amount;
        address payable recipient;
    }

    struct BasicOrderParameters {
        address considerationToken; // address(0) for native
        uint256 considerationIdentifier;
        uint256 considerationAmount;
        address payable offerer;
        address zone;
        address offerToken;
        uint256 offerIdentifier; // tokenId
        uint256 offerAmount; // 1 for ERC721
        ItemType basicOrderType;
        uint256 startTime;
        uint256 endTime;
        bytes32 zoneHash;
        uint256 salt;
        bytes32 offererConduitKey;
        bytes32 fulfillerConduitKey;
        uint256 totalOriginalAdditionalRecipients;
        AdditionalRecipient[] additionalRecipients;
        bytes signature;
    }

    function fulfillBasicOrder(BasicOrderParameters calldata parameters) external payable returns (bool fulfilled);
}
