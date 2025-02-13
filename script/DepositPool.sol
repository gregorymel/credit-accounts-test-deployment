// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {console} from "forge-std/console.sol";

// helpers
import {JsonHelper} from "./helpers/JsonHelper.sol";
import {BaseDeploymentHelper} from "./helpers/BaseDeploymentHelper.sol";

contract DepositPool is JsonHelper, BaseDeploymentHelper {
    function run() public loadMarketJSON loadCreditSuiteJSON {
        address cm = creditSuiteJSON.creditManager;
        address pool = marketJSON.pool;

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);

        vm.startBroadcast(deployer);
        IERC20(USDC).approve(address(pool), 1e6); // 1 USDC
        IPoolV3(pool).depositWithReferral(1e6, deployer, 0);
        vm.stopBroadcast();

        uint256 borrowable = IPoolV3(pool).creditManagerBorrowable(cm);
        console.log("borrowable", borrowable);
    }
}
