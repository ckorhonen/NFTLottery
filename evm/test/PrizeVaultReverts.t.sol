// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PrizeVault} from "src/PrizeVault.sol";

contract PrizeVaultRevertsTest is Test {
    function test_NotController_Reverts() public {
        PrizeVault vault = new PrizeVault(address(this));
        vm.expectRevert(PrizeVault.NotController.selector);
        vault.recordERC20(1, address(0x1234), 1);
    }
}

