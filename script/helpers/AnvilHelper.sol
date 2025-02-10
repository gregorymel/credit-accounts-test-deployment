// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

contract AnvilHelper is Script {
    // helper accounts
    uint256 internal defaultPK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function anvil_impersonateAccount(address account) internal {
        string memory params = string(abi.encodePacked("[\"", vm.toString(account), "\"]"));
        vm.rpc("local", "anvil_impersonateAccount", params);
    }

    function anvil_setBalance(address account, uint256 balance) internal {
        string memory params = string(abi.encodePacked("[\"", vm.toString(account), "\",", vm.toString(balance), "]"));
        vm.rpc("local", "anvil_setBalance", params);
    }

    function isAnvil() internal view returns (bool) {
        return block.chainid == 31337;
    }
}
