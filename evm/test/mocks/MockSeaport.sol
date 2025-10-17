// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISeaport} from "src/executors/ISeaport.sol";

contract MockSeaport is ISeaport {
    function fulfillBasicOrder(
        BasicOrderParameters calldata /*parameters*/
    )
        external
        payable
        returns (bool)
    {
        return true; // pretend success, transfers are handled outside in tests
    }
}

