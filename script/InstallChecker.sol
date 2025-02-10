// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// Standard Libraries and Interfaces
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Gearbox Protocol Imports
import {MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditFacadeV3Multicall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {MultiCallBuilder} from "@gearbox-protocol/core-v3/contracts/test/lib/MultiCallBuilder.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IWETH} from "@gearbox-protocol/core-v3/contracts/interfaces/external/IWETH.sol";

// Credit Accounts Imports
import {SafeCreditAccount} from "credit-accounts/src/safe/CreditAccount.sol";
import {ISafe, Enum} from "credit-accounts/src/safe/interfaces/ISafe.sol";
import {SafeCreditAccountFactory} from "credit-accounts/src/safe/CreditAccountFactory.sol";

// Local Project Imports
import {CreditFacadeV3_Extension} from "../src/credit/CreditFacadeV3_Extension.sol";
import {BaseDeploymentHelper} from "./helpers/BaseDeploymentHelper.sol";

contract InstallChecker is Script, BaseDeploymentHelper {
    // Owner of credit account
    uint256 internal immutable creditAccountOwnerPK;
    address internal immutable creditAccountOwner;

    constructor() {
        (creditAccountOwnerPK, creditAccountOwner) = _generateAccount("CREDIT_ACCOUNT_OWNER");
    }

    function _checkProperWork(address cm, address pool) internal {
        // Advance the block number once before opening the credit account.
        vm.roll(block.number + 1);

        // Open the credit account and obtain a reference to the credit facade.
        (address creditAccount, CreditFacadeV3_Extension creditFacade) = _openCreditAccount(cm);

        // Check that market is deployed and configured correctly
        _depositFunds(cm, pool);
        _increaseDebtAndUpdateQuota(creditAccount, creditFacade);
        _executeSafeTransaction(creditAccount);
    }

    /// @dev Increases debt and updates quota using a multicall.
    function _increaseDebtAndUpdateQuota(address creditAccount, CreditFacadeV3_Extension creditFacade) internal {
        _mintWETH(creditAccount, 1e18);
        _mintUSDT(creditAccount, 1e6);
        _mintDAI(creditAccount, 1e18);

        vm.startPrank(creditAccount);
        creditFacade.multicall(
            creditAccount,
            MultiCallBuilder.build(
                MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeCall(ICreditFacadeV3Multicall.increaseDebt, (1e6))
                }),
                MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeCall(ICreditFacadeV3Multicall.updateQuota, (USDT, 2e6, 0))
                }),
                // MultiCall({
                //     target: address(creditFacade),
                //     callData: abi.encodeCall(ICreditFacadeV3Multicall.updateQuota, (WETH, 1e6, 0))
                // }),
                MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeCall(ICreditFacadeV3Multicall.updateQuota, (DAI, 2e6, 0))
                })
            )
        );
        vm.stopPrank();
    }

    /// @dev Executes a safe transaction on the credit account.
    function _executeSafeTransaction(address creditAccount) internal {
        ISafe safeCreditAccount = ISafe(creditAccount);
        (bool success, bytes memory data) = address(safeCreditAccount).staticcall(abi.encodeWithSignature("nonce()"));
        require(success, "Static call to nonce() failed");
        uint256 nonce = abi.decode(data, (uint256));

        bytes32 txHash = safeCreditAccount.getTransactionHash(
            address(0), 0, "", Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), nonce
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creditAccountOwnerPK, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        address realCreditManager = ICreditAccountV3(creditAccount).creditManager();
        address realCreditFacade = ICreditManagerV3(realCreditManager).creditFacade();
        console.log("realCreditManager", realCreditManager);
        console.log("realCreditFacade", realCreditFacade);

        vm.startPrank(creditAccountOwner);
        safeCreditAccount.execTransaction(
            address(0), 0, "", Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signature
        );
        vm.stopPrank();
    }

    /// @dev Opens a credit account using the deployed credit suite.
    function _openCreditAccount(address cm)
        internal
        returns (address creditAccount, CreditFacadeV3_Extension creditFacade)
    {
        creditFacade = CreditFacadeV3_Extension(ICreditManagerV3(cm).creditFacade());
        address onBehalfOf = creditAccountOwner;
        vm.startPrank(onBehalfOf);
        address[] memory owners = new address[](1);
        owners[0] = onBehalfOf;
        uint256 threshold = 1;
        bytes32 accountSalt = keccak256(abi.encodePacked(owners, threshold));
        address predictedCreditAccount =
            SafeCreditAccountFactory(ICreditManagerV3(cm).accountFactory()).predictCreditAccountAddress(accountSalt);
        creditAccount = creditFacade.openCreditSmartAccount(onBehalfOf, predictedCreditAccount);
        console.log("creditAccount", creditAccount);
        vm.stopPrank();
        return (creditAccount, creditFacade);
    }

    /// @dev Deposits funds into the pool and prints liquidity and credit parameters.
    function _depositFunds(address cm, address pool) internal {
        address supplier = makeAddr("SUPPLIER");
        _mintUSDC(supplier, 100e6);

        // vm.deal(supplier, 2e18);
        // IWETH(WETH).deposit{value: 1e18}();

        vm.startPrank(supplier);
        IERC20(USDC).approve(address(pool), 100e6);
        IPoolV3(pool).depositWithReferral(100e6, supplier, 0);
        vm.stopPrank();

        uint256 availableLiquidity = IPoolV3(pool).availableLiquidity();
        console.log("availableLiquidity", availableLiquidity);
        uint256 debtLimit = IPoolV3(pool).creditManagerDebtLimit(cm);
        console.log("debtLimit", debtLimit);
        uint256 borrowable = IPoolV3(pool).creditManagerBorrowable(cm);
        console.log("borrowable", borrowable);
    }

    function _mintWETH(address to, uint256 amount) internal {
        address holder = makeAddr("WETH_HOLDER");
        vm.deal(holder, amount);

        vm.startPrank(holder);
        IWETH(WETH).deposit{value: amount}();
        IERC20(WETH).transfer(to, amount);
        vm.stopPrank();
    }

    function _mintToken(address token, address fatTokenHolder, address to, uint256 amount) internal {
        vm.prank(fatTokenHolder);
        IERC20(token).transfer(to, amount);
    }

    function _mintUSDC(address to, uint256 amount) internal {
        _mintToken(USDC, FAT_USDC_HOLDER, to, amount);
    }

    function _mintUSDT(address to, uint256 amount) internal {
        _mintToken(USDT, FAT_USDT_HOLDER, to, amount);
    }

    function _mintDAI(address to, uint256 amount) internal {
        _mintToken(DAI, FAT_DAI_HOLDER, to, amount);
    }

    function _generateAccount(string memory name) internal returns (uint256, address) {
        uint256 pk = uint256(keccak256(abi.encodePacked(name)));
        address account = vm.addr(pk);
        vm.label(account, name);
        return (pk, account);
    }
}
