// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditConfiguratorV3.sol";
import {CreditManagerV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditManagerV3.sol";
import {CreditFactory} from "governance/contracts/factories/CreditFactory.sol";

contract CreditFactoryV32 is CreditFactory {
    constructor(address addressProvider_) CreditFactory(addressProvider_) {}

    function version() public pure override returns (uint256) {
        return 3_20;
    }
}

contract CreditManagerV32 is CreditManagerV3 {
    constructor(
        address _pool,
        address _accountFactory,
        address _priceOracle,
        uint8 _maxEnabledTokens,
        uint16 _feeInterest,
        uint16 _feeLiquidation,
        uint16 _liquidationPremium,
        uint16 _feeLiquidationExpired,
        uint16 _liquidationPremiumExpired,
        string memory _name
    )
        CreditManagerV3(
            _pool,
            _accountFactory,
            _priceOracle,
            _maxEnabledTokens,
            _feeInterest,
            _feeLiquidation,
            _liquidationPremium,
            _feeLiquidationExpired,
            _liquidationPremiumExpired,
            _name
        )
    {}

    function version() public pure override returns (uint256) {
        return 3_20;
    }
}

contract CreditConfiguratorV32 is CreditConfiguratorV3 {
    constructor(address _creditManager) CreditConfiguratorV3(_creditManager) {}

    function version() public pure override returns (uint256) {
        return 3_20;
    }
}
