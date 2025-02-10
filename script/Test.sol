// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {IPhantomToken} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPhantomToken.sol";

contract TestContract {
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    uint256 internal _stateVar1;
    uint256 internal _stateVar2;

    function test() external {
        try IPhantomToken(WETH).getPhantomTokenInfo() {
            _stateVar1++;
        } catch {
            _stateVar2++;
        }
    }

    function getStateVar1() external view returns (uint256) {
        return _stateVar1;
    }

    function getStateVar2() external view returns (uint256) {
        return _stateVar2;
    }
}

contract Test is Script {
    // uint256 internal defaultPK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    function run() public {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        uint256 balance = deployer.balance;

        console2.log("Test:deployer", deployer);
        console2.log("Test:balance", balance);

        // vm.startSnapshotGas("Test");
        // vm.startBroadcast(pk);
        // uint256 gasBefore = gasleft();
        // try IPhantomToken(WETH).getPhantomTokenInfo() {
        //     // console2.log("Test:test");
        // } catch {
        //     // console2.log("Test:test");
        // }
        // uint256 gasAfter = gasleft();
        // console2.log("Test:gasAfter", gasBefore - gasAfter);
        // vm.stopBroadcast();
        // vm.stopSnapshotGas("Test");

        vm.startBroadcast(pk);
        TestContract testContract = TestContract(0xE5ba5F2Cc247216fA9b4e7D84154E261C7203925);

        testContract.test();
        console2.log("Test:testContract", testContract.getStateVar1());
        console2.log("Test:testContract", testContract.getStateVar2());
        // address testContract = address(new TestContract());

        // console2.log("Test:testContract", testContract);
        vm.stopBroadcast();
    }
}
