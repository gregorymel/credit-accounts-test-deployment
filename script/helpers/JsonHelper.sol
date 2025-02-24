// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

struct AddressesJSON {
    address addressProvider;
    address bytecodeRepository;
    address instanceManager;
    address multisig;
}

struct MarketJSON {
    address marketConfigurator;
    address pool;
}

/// @dev fileds should be ordered as they would be in the json file
struct CreditSuiteJSON {
    address creditAccountFactory;
    address creditAccountHelper;
    address creditFacade;
    address creditManager;
}

contract JsonHelper is Script {
    /// Parsed JSON files
    AddressesJSON internal addressesJSON;
    MarketJSON internal marketJSON;
    CreditSuiteJSON internal creditSuiteJSON;

    modifier loadAddressesJSON() {
        _loadAddressesJSON();
        _;
    }

    modifier serializeAddressesJSON() {
        _;
        _serializeAddressesJSON();
    }

    modifier loadMarketJSON() {
        _loadMarketJSON();
        _;
    }

    modifier serializeMarketJSON() {
        _;
        _serializeMarketJSON();
    }

    modifier loadCreditSuiteJSON() {
        _loadCreditSuiteJSON();
        _;
    }

    modifier serializeCreditSuiteJSON() {
        _;
        _serializeCreditSuiteJSON();
    }

    function _loadAddressesJSON() internal {
        string memory path = string(abi.encodePacked("./jsons/", vm.toString(block.chainid), "/addresses.json"));
        string memory json = vm.readFile(path);
        addressesJSON = abi.decode(vm.parseJson(json), (AddressesJSON));
    }

    function _serializeAddressesJSON() internal {
        string memory json = vm.serializeAddress("addresses", "addressProvider", addressesJSON.addressProvider);
        json = vm.serializeAddress("addresses", "bytecodeRepository", addressesJSON.bytecodeRepository);
        json = vm.serializeAddress("addresses", "instanceManager", addressesJSON.instanceManager);
        json = vm.serializeAddress("addresses", "multisig", addressesJSON.multisig);
        string memory path = string(abi.encodePacked("./jsons/", vm.toString(block.chainid), "/addresses.json"));
        vm.writeJson(json, path);
    }

    function _loadMarketJSON() internal {
        string memory path = string(abi.encodePacked("./jsons/", vm.toString(block.chainid), "/market.json"));
        string memory json = vm.readFile(path);
        marketJSON = abi.decode(vm.parseJson(json), (MarketJSON));
    }

    function _serializeMarketJSON() internal {
        string memory json = vm.serializeAddress("market", "marketConfigurator", marketJSON.marketConfigurator);
        json = vm.serializeAddress("market", "pool", marketJSON.pool);
        string memory path = string(abi.encodePacked("./jsons/", vm.toString(block.chainid), "/market.json"));
        vm.writeJson(json, path);
    }

    function _loadCreditSuiteJSON() internal {
        string memory path = string(abi.encodePacked("./jsons/", vm.toString(block.chainid), "/creditSuite.json"));
        string memory json = vm.readFile(path);
        creditSuiteJSON = abi.decode(vm.parseJson(json), (CreditSuiteJSON));
    }

    function _serializeCreditSuiteJSON() internal {
        string memory json =
            vm.serializeAddress("creditSuite", "creditAccountFactory", creditSuiteJSON.creditAccountFactory);
        json = vm.serializeAddress("creditSuite", "creditAccountHelper", creditSuiteJSON.creditAccountHelper);
        json = vm.serializeAddress("creditSuite", "creditFacade", creditSuiteJSON.creditFacade);
        json = vm.serializeAddress("creditSuite", "creditManager", creditSuiteJSON.creditManager);
        string memory path = string(abi.encodePacked("./jsons/", vm.toString(block.chainid), "/creditSuite.json"));
        vm.writeJson(json, path);
    }
}
