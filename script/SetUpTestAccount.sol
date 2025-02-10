// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeploymentHelper} from "./BaseDeploymentHelper.sol";
import {ISafe} from "../src/CreditAccountHelper.sol";
import {
    CreditAccountHelper, MultiCall, ICreditFacadeV3Multicall, ICreditFacadeV3
} from "../src/CreditAccountHelper.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IWETH} from "@gearbox-protocol/core-v3/contracts/interfaces/external/IWETH.sol";

contract SetUpTestAccount is Script, BaseDeploymentHelper {
    // helper accounts
    uint256 internal defaultPK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() public {
        _impersonateAccount(FAT_USDC_HOLDER);
        _impersonateAccount(FAT_USDT_HOLDER);
        _impersonateAccount(FAT_DAI_HOLDER);

        address accountOwner = 0xdF61f9B6C039456d33776a1b6931B2E5D761Cd8f;
        address creditAccount = 0x4549C4d4f8C6A37A3355a30787CDFEA7f7C13643;

        vm.startBroadcast(defaultPK);
        payable(accountOwner).transfer(1e18);
        IWETH(WETH).deposit{value: 1e18}();
        IERC20(WETH).transfer(creditAccount, 1e18);
        vm.stopBroadcast();

        vm.broadcast(FAT_USDC_HOLDER);
        IERC20(USDC).transfer(creditAccount, 1e6);

        vm.broadcast(FAT_USDT_HOLDER);
        IERC20(USDT).transfer(creditAccount, 100e6);

        vm.broadcast(FAT_DAI_HOLDER);
        IERC20(DAI).transfer(creditAccount, 100e18);

        _depositUSDCToPool();
    }

    function _impersonateAccount(address account) internal {
        string memory params = string(abi.encodePacked("[\"", vm.toString(account), "\"]"));
        vm.rpc("local", "anvil_impersonateAccount", params);
    }

    function _depositUSDCToPool() internal {
        // _impersonateAccount(FAT_USDC_HOLDER);

        address cm = 0x001f9287458360aF005C292E947C3b553cb31877;
        address pool = ICreditManagerV3(cm).pool();

        vm.startBroadcast(FAT_USDC_HOLDER);
        IERC20(USDC).approve(address(pool), 100e6);
        IPoolV3(pool).depositWithReferral(100e6, FAT_USDC_HOLDER, 0);
        vm.stopBroadcast();

        uint256 borrowable = IPoolV3(pool).creditManagerBorrowable(cm);
        console.log("borrowable", borrowable);
    }
}
