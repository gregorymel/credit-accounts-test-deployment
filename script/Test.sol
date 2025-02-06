// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeploymentHelper} from "./BaseDeploymentHelper.sol";

contract SetUpTestAccount is Script, BaseDeploymentHelper {
    // helper accounts
    uint256 internal defaultPK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() public {
        _impersonateAccount(FAT_USDC_HOLDER);
        _impersonateAccount(FAT_USDT_HOLDER);
        _impersonateAccount(FAT_DAI_HOLDER);

        address to = 0x4549C4d4f8C6A37A3355a30787CDFEA7f7C13643;

        vm.broadcast(FAT_USDC_HOLDER);
        IERC20(USDC).transfer(to, 100e6);

        vm.broadcast(FAT_USDT_HOLDER);
        IERC20(USDT).transfer(to, 100e6);

        vm.broadcast(FAT_DAI_HOLDER);
        IERC20(DAI).transfer(to, 100e18);
    }

    function _impersonateAccount(address account) internal {
        string memory params = string(abi.encodePacked("[\"", vm.toString(account), "\"]"));
        vm.rpc("local", "anvil_impersonateAccount", params);
    }
}
