// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {CreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditFacadeV3.sol";
import {ICreditManagerV3, ManageDebtAction} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ICreditFacadeV3Hooks} from "../interfaces/ICreditFacadeV3Hooks.sol";
import {ICreditFacadeV3_Extension} from "../interfaces/ICreditFacadeV3_Extension.sol";

import {PERCENTAGE_FACTOR} from "@gearbox-protocol/core-v3/contracts/libraries/Constants.sol";

contract CreditFacadeV3_Extension is CreditFacadeV3, ICreditFacadeV3Hooks, ICreditFacadeV3_Extension {
    uint256 internal _enabledTokensMask;

    /// @dev Context of the credit account being opened
    address internal _onBehalfOf;

    constructor(
        address _acl,
        address _creditManager,
        address _lossPolicy,
        address _botList,
        address _weth,
        address _degenNFT,
        bool _expirable
    ) CreditFacadeV3(_acl, _creditManager, _lossPolicy, _botList, _weth, _degenNFT, _expirable) {}

    /// @dev Ensures that function caller is `creditAccount` itself
    modifier creditAccountOnly() {
        _checkCreditAccountOwner(msg.sender);
        _;
    }

    modifier whenExecuting() {
        address creditAccount = _getActiveCreditAccountOrRevert();
        if (creditAccount != msg.sender) revert();
        _;
    }

    function openCreditSmartAccount(address onBehalfOf, address expectedCreditAccount)
        external
        payable
        whenNotPaused
        whenNotExpired
        nonReentrant
        returns (address creditAccount)
    {
        _onBehalfOf = onBehalfOf;

        creditAccount = ICreditManagerV3(creditManager).openCreditAccount({onBehalfOf: expectedCreditAccount});
        if (creditAccount != expectedCreditAccount) revert("CreditFacadeV3_Extension: creditAccount mismatch");
        emit OpenCreditAccount(creditAccount, onBehalfOf, msg.sender, 0 /* referral code*/ );

        _onBehalfOf = address(0);
    }

    function increaseDebt(uint256 amount) external whenNotPaused whenNotExpired whenExecuting creditAccountOnly {
        _manageDebt(msg.sender, amount, _enabledTokensMask, ManageDebtAction.INCREASE_DEBT);
    }

    function decreaseDebt(uint256 amount) external whenNotPaused whenNotExpired whenExecuting creditAccountOnly {
        _manageDebt(msg.sender, amount, _enabledTokensMask, ManageDebtAction.DECREASE_DEBT);
    }

    function updateQuota(address token, int96 quotaChange, uint96 minQuota)
        external
        whenNotPaused
        whenNotExpired
        whenExecuting
        creditAccountOnly
    {
        (_enabledTokensMask,) = _updateQuota(msg.sender, msg.data[4:], _enabledTokensMask, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        Collateral check hooks
    //////////////////////////////////////////////////////////////////////////*/

    function getOpenCreditAccountContextOrRevert() external view override returns (address) {
        if (_onBehalfOf == address(0)) revert("CreditFacadeV3_Extension: _onBehalfOf is not set");
        return _onBehalfOf;
    }

    function preExecutionCheck() external override creditAccountOnly whenNotPaused whenNotExpired {
        address creditAccount = msg.sender;
        _setActiveCreditAccount(creditAccount);

        _enabledTokensMask = _enabledTokensMaskOf(creditAccount);
    }

    function postExecutionCheck() external override whenExecuting {
        address creditAccount = msg.sender;
        _unsetActiveCreditAccount();

        _fullCollateralCheck({
            creditAccount: creditAccount,
            enabledTokensMask: _enabledTokensMask,
            collateralHints: new uint256[](0),
            minHealthFactor: PERCENTAGE_FACTOR,
            useSafePrices: false
        });
    }

    function _getActiveCreditAccountOrRevert() internal view returns (address) {
        return ICreditManagerV3(creditManager).getActiveCreditAccountOrRevert();
    }
}
