// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IPriceOraclev3 {
    function convertToUSD(uint256 amount, address token) external view returns (uint256);
}

interface ICreditManagerV3 {
    function creditFacade() external view returns (address);
    function priceOracle() external view returns (address);
    function poolQuotaKeeper() external view returns (address);
}

interface ICreditFacadeV3 {
    struct MultiCall {
        address target;
        bytes callData;
    }

    function multicall(address creditAccount, MultiCall[] calldata calls) external payable;
}

interface ICreditFacadeV3Multicall {
    function increaseDebt(uint256 amount) external;
    function decreaseDebt(uint256 amount) external;
    function updateQuota(address token, int96 quotaChange, uint96 minQuota) external;
}

interface IPoolQuotaKeeperV3 {
    function getQuota(address creditAccount, address token)
        external
        view
        returns (uint96 quota, uint192 cumulativeIndexLU);
}

interface ICreditAccountV3 {
    function factory() external view returns (address);
}

interface ISafeCreditAccountFactory {
    function predictCreditAccountAddress(bytes32 salt) external view returns (address safeProxy);
}

contract CreditAccountHelper {
    struct AccountInfo {
        bool isCreditAccount;
        bool isCreditAccountCreated;
        address creditAccountAddress;
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
