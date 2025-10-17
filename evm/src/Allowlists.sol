// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CollectionAllowlist is Ownable2Step {
    mapping(address => bool) public isAllowed;
    mapping(address => bool) private _listed;
    address[] private _items;
    event Set(address indexed collection, bool allowed);
    constructor(address owner_) Ownable(owner_) {}

    function set(address collection, bool allowed) external onlyOwner {
        isAllowed[collection] = allowed;
        if (!_listed[collection]) _listed[collection] = true;
        _items.push(collection);
        emit Set(collection, allowed);
    }

    function isCollectionAllowed(address token) external view returns (bool) {
        return isAllowed[token];
    }

    function length() external view returns (uint256) {
        return _items.length;
    }

    function at(uint256 i) external view returns (address item, bool allowed) {
        item = _items[i];
        allowed = isAllowed[item];
    }
}

contract TokenAllowlist is Ownable2Step {
    mapping(address => bool) public isAllowed;
    mapping(address => bool) private _listed;
    address[] private _items;
    event Set(address indexed token, bool allowed);
    constructor(address owner_) Ownable(owner_) {}

    function set(address token, bool allowed) external onlyOwner {
        isAllowed[token] = allowed;
        if (!_listed[token]) _listed[token] = true;
        _items.push(token);
        emit Set(token, allowed);
    }

    function isTokenAllowed(address token) external view returns (bool) {
        return isAllowed[token];
    }

    function length() external view returns (uint256) {
        return _items.length;
    }

    function at(uint256 i) external view returns (address item, bool allowed) {
        item = _items[i];
        allowed = isAllowed[item];
    }
}
