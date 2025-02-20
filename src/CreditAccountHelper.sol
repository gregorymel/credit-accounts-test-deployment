// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IPriceOraclev3 {
    function convertToUSD(uint256 amount, address token) external view returns (uint256);
}

interface ICreditManagerV3 {
    enum CollateralCalcTask {
        GENERIC_PARAMS,
        DEBT_ONLY,
        FULL_COLLATERAL_CHECK_LAZY,
        DEBT_COLLATERAL,
        DEBT_COLLATERAL_SAFE_PRICES
    }

    struct CollateralDebtData {
        uint256 debt;
        uint256 cumulativeIndexNow;
        uint256 cumulativeIndexLastUpdate;
        uint128 cumulativeQuotaInterest;
        uint256 accruedInterest;
        uint256 accruedFees;
        uint256 totalDebtUSD;
        uint256 totalValue;
        uint256 totalValueUSD;
        uint256 twvUSD;
        uint256 enabledTokensMask;
        uint256 quotedTokensMask;
        address[] quotedTokens;
        address _poolQuotaKeeper;
    }

    function creditFacade() external view returns (address);
    function priceOracle() external view returns (address);
    function pool() external view returns (address);
    function poolQuotaKeeper() external view returns (address);
    function calcDebtAndCollateral(address creditAccount, CollateralCalcTask task)
        external
        view
        returns (CollateralDebtData memory cdd);
}

struct MultiCall {
    address target;
    bytes callData;
}

interface ICreditFacadeV3Multicall {
    function increaseDebt(uint256 amount) external;
    function decreaseDebt(uint256 amount) external;
    function updateQuota(address token, int96 quotaChange, uint96 minQuota) external;
}

interface ICreditFacadeV3 {
    struct DebtLimits {
        uint128 minDebt;
        uint128 maxDebt;
    }

    function debtLimits() external view returns (DebtLimits memory);
    function creditManager() external view returns (address);
}

interface IPoolQuotaKeeperV3 {
    function getQuota(address creditAccount, address token)
        external
        view
        returns (uint96 quota, uint192 cumulativeIndexLU);
}

interface IPoolV3 {
    function creditManagerBorrowable(address creditManager) external view returns (uint256);
}

interface ICreditAccountV3 {
    function factory() external view returns (address);
}

interface ISafe {
    enum Operation {
        Call,
        DelegateCall
    }

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external returns (bool success);

    function nonce() external view returns (uint256);
}

interface IMultiSend {
    function multiSend(bytes memory transactions) external payable;
}

interface ISafeCreditAccountFactory {
    function predictCreditAccountAddress(bytes32 salt) external view returns (address safeProxy);
}

contract CreditAccountHelper {
    using Address for address;

    struct AccountInfo {
        bool isCreditAccount;
        bool isCreditAccountCreated;
        address creditAccountAddress;
    }

    function multicall(MultiCall[] calldata calls) external {
        for (uint256 i = 0; i < calls.length; i++) {
            calls[i].target.functionCall(calls[i].callData);
        }
    }

    /// @dev Predicts the address of a safe_1_1 credit account
    function predictCreditAccountAddress(address creditAccountFactory, address onBehalfOf)
        external
        view
        returns (address creditAccount)
    {
        return _predictCreditAccountAddress(creditAccountFactory, onBehalfOf);
    }

    /// @dev Checks if an account is a credit account
    function checkAccount(address account, address creditAccountFactory) external view returns (AccountInfo memory) {
        AccountInfo memory info;

        if (account.code.length != 0) {
            try ICreditAccountV3(account).factory() returns (address factory) {
                info.isCreditAccount = true;
                info.isCreditAccountCreated = true;
                info.creditAccountAddress = account;
            } catch {
                info.isCreditAccount = false;
                info.isCreditAccountCreated = false;
                info.creditAccountAddress = address(0);
            }
        } else {
            address creditAccount = _predictCreditAccountAddress(creditAccountFactory, account);

            info.isCreditAccount = false;
            info.isCreditAccountCreated = (creditAccount.code.length != 0);
            info.creditAccountAddress = creditAccount;
        }

        return info;
    }

    function getAccountDebtAndTWV(address creditManager, address creditAccount)
        external
        view
        returns (uint256 debtPrincipal, uint256 totalDebt, uint256 twv)
    {
        ICreditManagerV3.CollateralDebtData memory cdd = ICreditManagerV3(creditManager).calcDebtAndCollateral(
            creditAccount, ICreditManagerV3.CollateralCalcTask.DEBT_COLLATERAL
        );

        debtPrincipal = cdd.debt;
        totalDebt = cdd.debt + cdd.accruedInterest + cdd.accruedFees;
        twv = cdd.twvUSD;
    }

    function getAccountDebtLimits(address creditFacade, address)
        external
        view
        returns (uint256 minDebt, uint256 maxDebt, uint256 borrowable)
    {
        ICreditFacadeV3.DebtLimits memory debtLimits = ICreditFacadeV3(creditFacade).debtLimits();

        address cm = ICreditFacadeV3(creditFacade).creditManager();
        address pool = ICreditManagerV3(cm).pool();
        uint256 borrowable = IPoolV3(pool).creditManagerBorrowable(cm);

        return (debtLimits.minDebt, debtLimits.maxDebt, borrowable);
    }

    /// @dev Gets the prices of a list of tokens from price oracle
    function getTokensPricesInUSD(address creditManager, address[] memory tokens, uint256[] memory amounts)
        external
        view
        returns (uint256[] memory prices)
    {
        prices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[i] = _getTokenPriceInUSD(creditManager, tokens[i], amounts[i]);
        }
    }

    /// @dev Gets the quotas of a credit account
    function getCreditAccountQuotas(address creditManager, address creditAccount, address[] memory tokens)
        external
        view
        returns (uint96[] memory quotas)
    {
        address poolQuotaKeeper = ICreditManagerV3(creditManager).poolQuotaKeeper();
        quotas = new uint96[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            (quotas[i],) = IPoolQuotaKeeperV3(poolQuotaKeeper).getQuota(creditAccount, tokens[i]);
        }

        return quotas;
    }

    function _getTokenPriceInUSD(address creditManager, address token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        address priceOracle = ICreditManagerV3(creditManager).priceOracle();
        return IPriceOraclev3(priceOracle).convertToUSD(amount, token);
    }

    function _predictCreditAccountAddress(address creditAccountFactory, address onBehalfOf)
        internal
        view
        returns (address creditAccount)
    {
        address[] memory owners = new address[](1);
        owners[0] = onBehalfOf;
        uint256 threshold = 1;
        bytes32 accountSalt = keccak256(abi.encodePacked(owners, threshold));
        return ISafeCreditAccountFactory(creditAccountFactory).predictCreditAccountAddress(accountSalt);
    }
}
