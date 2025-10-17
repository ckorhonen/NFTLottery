// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ERC1155 where each token id represents a roundId; amount is number of tickets.
contract Ticket1155 is ERC1155, Ownable2Step {
    string private _uriTemplate;
    address public minter;

    error NotMinter();

    constructor(string memory uriTemplate_, address owner_) ERC1155("") Ownable(owner_) {
        _uriTemplate = uriTemplate_;
    }

    function setMinter(address m) external onlyOwner {
        minter = m;
    }

    function uri(uint256) public view override returns (string memory) {
        return _uriTemplate;
    }

    function mint(address to, uint256 id, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        _mint(to, id, amount, "");
    }
}
