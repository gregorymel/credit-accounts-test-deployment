// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// Forge Std & Testing
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UploadableContract, GlobalSetup} from "governance/contracts/test/helpers/GlobalSetup.sol";

// OpenZeppelin
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

// Gearbox Core Interfaces
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ICreditFacadeV3, MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditFacadeV3Multicall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IWETH} from "@gearbox-protocol/core-v3/contracts/interfaces/external/IWETH.sol";
import {ITumblerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ITumblerV3.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
// Gearbox Utilities
import {MultiCallBuilder} from "@gearbox-protocol/core-v3/contracts/test/lib/MultiCallBuilder.sol";

// Governance Contracts
import {InstanceManager} from "governance/contracts/instance/InstanceManager.sol";
import {IAddressProvider} from "governance/contracts/interfaces/IAddressProvider.sol";
import {
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_POOL_FACTORY,
    NO_VERSION_CONTROL
} from "governance/contracts/libraries/ContractLiterals.sol";
import {MarketConfigurator} from "governance/contracts/market/MarketConfigurator.sol";
import {MarketConfiguratorFactory} from "governance/contracts/instance/MarketConfiguratorFactory.sol";

// Governance Types & Factories
import {CrossChainCall, DeployParams, Call} from "governance/contracts/interfaces/Types.sol";
import {CreditFacadeParams, CreditManagerParams} from "governance/contracts/factories/CreditFactory.sol";
import {IConfigureActions as IPoolConfigureActions} from "governance/contracts/factories/PoolFactory.sol";
import {IConfigureActions as ICreditConfigureActions} from "governance/contracts/factories/CreditFactory.sol";

// Account Management
import {SafeCreditAccountFactory} from "credit-accounts/src/safe/CreditAccountFactory.sol";
import {SafeCreditAccount} from "credit-accounts/src/safe/CreditAccount.sol";
import {ISafe, Enum} from "credit-accounts/src/safe/interfaces/ISafe.sol";

// Local Extensions & Utilities
import {CreditFacadeV3_Extension} from "../src/credit/CreditFacadeV3_Extension.sol";
import {SafeDeployments} from "./SafeDeploymentLib.sol";

// Helpers
import {CreditAccountHelper} from "../src/CreditAccountHelper.sol";
import {BaseDeploymentHelper} from "./BaseDeploymentHelper.sol";

/**
 * @title TestnetInstall
 * @notice This deployment script installs the test market and credit suite on Base.
 */
contract TestnetInstall is Script, GlobalSetup, BaseDeploymentHelper {
    // State variables
    address internal riskCurator;
    address internal deployer;
    // Owner of credit account
    uint256 internal immutable creditAccountOwnerPK;
    address internal immutable creditAccountOwner;

    // helper accounts
    uint256 internal defaultPK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    address internal GEAR;
    address TREASURY;

    string constant name = "Test Market USDC";
    string constant symbol = "dUSDC";

    constructor() GlobalSetup() {
        (creditAccountOwnerPK, creditAccountOwner) = _generateAccount("CREDIT_ACCOUNT_OWNER");
    }

    function run() public {
        uint256 deployerPK = defaultPK;
        // uint256 deployerPK = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPK);
        riskCurator = deployer;

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        IERC20(USDC).transfer(deployer, 1e5);
        vm.stopBroadcast();

        // riskCurator = vm.addr(_generatePrivateKey("RISK_CURATOR"));
        vm.label(deployer, "DEPLOYER");
        vm.label(riskCurator, "RISK_CURATOR");

        vm.startBroadcast(deployerPK);

        _fundActors();

        _setUp();
        (address pool, address cm) = _createMarket();

        address helper = address(new CreditAccountHelper());
        console.log("--------------------------------");
        console.log("CreditManager", cm);
        console.log("CreditFacade", ICreditManagerV3(cm).creditFacade());
        console.log("CreditAccountFactory", ICreditManagerV3(cm).accountFactory());
        console.log("CreditAccountHelper", helper);
        console.log("--------------------------------");
        console.log("Finish deployment!");

        vm.stopBroadcast();

        // Check that the market is deployed and configured correctly if dry run
        // if (vm.isContext(VmSafe.ForgeContext.ScriptDryRun)) {
        //     _checkProperWork(cm, pool);
        // }

        // vm.writeJson(json, path);
    }

    /**
     * @dev Sets up the instance: deploys base tokens, instance manager, activates instance,
     * sets account factory and global contracts, configures price feeds, etc.
     */
    function _setUp() internal {
        TREASURY = vm.addr(_generatePrivateKey("TREASURY"));
        GEAR = address(new ERC20("Gearbox", "GEAR"));

        _setUpInstanceManager();

        // Activate the instance using a generated cross chain call
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = _generateActivateCall(0, instanceOwner, TREASURY, WETH, GEAR);
        _submitAndSignOrExecuteProposal("Activate instance", calls);

        _setCoreContracts();
        _setupAccountFactoryAndFacade();
        _setUpGlobalContracts();

        // Set up price feeds and allow tokens
        _setupPriceFeedStore();
    }

    function _setupPriceFeedStore() internal {
        _addPriceFeed(CHAINLINK_ETH_USD, 1 days, "ETH/USD");
        _addPriceFeed(CHAINLINK_USDC_USD, 1 days, "USDC/USD");
        _addPriceFeed(CHAINLINK_USDT_USD, 1 days, "USDT/USD");
        _addPriceFeed(CHAINLINK_DAI_USD, 1 days, "DAI/USD");

        _allowPriceFeed(WETH, CHAINLINK_ETH_USD);
        _allowPriceFeed(USDC, CHAINLINK_USDC_USD);
        _allowPriceFeed(USDT, CHAINLINK_USDT_USD);
        _allowPriceFeed(DAI, CHAINLINK_DAI_USD);
    }

    /**
     * @dev Creates and configures the market and credit suite.
     */
    function _createMarket() internal returns (address, address) {
        // Retrieve required addresses from the instance manager & address provider.
        address ap = instanceManager.addressProvider();
        address mcf = IAddressProvider(ap).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
        address poolFactory = IAddressProvider(ap).getAddressOrRevert(AP_POOL_FACTORY, 3_10);

        // Fund the pool factory with a minimal USDC deposit.
        // _fundPoolFactory(poolFactory);
        _fundPoolFactoryUSDC(poolFactory);

        // Deploy the MarketConfigurator
        address mc = _deployMarketConfigurator(mcf);

        // Deploy the market and set up the credit suite.
        address pool = _deployMarket(mc, ap);
        address cm = _deployCreditSuite(mc, ap, pool);

        // Configure pool and credit suite
        _configurePool(mc, pool, cm);
        _configureCreditSuite(mc, cm);
        return (pool, cm);
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

    /// @dev Funds the pool factory with a minimal deposit.
    function _fundPoolFactory(address poolFactory) internal {
        IWETH(WETH).deposit{value: 1e5}();
        IERC20(WETH).transfer(poolFactory, 1e5);
    }

    function _fundPoolFactoryUSDC(address poolFactory) internal {
        // _mintUSDC(poolFactory, 1e5);
        _startPrankOrBroadcast(deployer);
        uint256 amount = IERC20(USDC).balanceOf(deployer);
        console.log("USDC balance", amount);
        IERC20(USDC).transfer(poolFactory, 1e5);
        _stopPrankOrBroadcast();
    }

    /// @dev Deploys the MarketConfigurator and logs the gas used.
    function _deployMarketConfigurator(address mcf) internal returns (address mc) {
        uint256 gasBefore = gasleft();
        _startPrankOrBroadcast(riskCurator);
        mc = MarketConfiguratorFactory(mcf).createMarketConfigurator(
            riskCurator, riskCurator, riskCurator, "Test Risk Curator", false
        );
        uint256 gasAfter = gasleft();
        console.log("createMarketConfigurator gasUsed", gasBefore - gasAfter);
        _stopPrankOrBroadcast();
        return mc;
    }

    /// @dev Creates the pool
    function _deployMarket(address mc, address ap) internal returns (address pool) {
        _startPrankOrBroadcast(riskCurator);
        // Predict the future market (pool) address.
        address predictedPool = MarketConfigurator(mc).previewCreateMarket(3_10, USDC, name, symbol);

        DeployParams memory interestRateModelParams = DeployParams({
            postfix: "LINEAR",
            salt: 0,
            constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
        });
        DeployParams memory rateKeeperParams =
            DeployParams({postfix: "TUMBLER", salt: 0, constructorParams: abi.encode(predictedPool, 0 days)});
        DeployParams memory lossPolicyParams =
            DeployParams({postfix: "DEFAULT", salt: 0, constructorParams: abi.encode(predictedPool, ap)});

        uint256 gasBefore = gasleft();

        // USDC is the underlying token
        pool = MarketConfigurator(mc).createMarket({
            minorVersion: 3_10,
            underlying: USDC,
            name: name,
            symbol: symbol,
            interestRateModelParams: interestRateModelParams,
            rateKeeperParams: rateKeeperParams,
            lossPolicyParams: lossPolicyParams,
            underlyingPriceFeed: CHAINLINK_USDC_USD
        });
        uint256 gasAfter = gasleft();
        console.log("createMarket gasUsed", gasBefore - gasAfter);

        // Ensure the preview matches the deployed pool.
        assertEq(predictedPool, pool);

        _stopPrankOrBroadcast();
        return pool;
    }

    /// @dev Creates the credit suite - credit manager, facade
    function _deployCreditSuite(address mc, address ap, address pool) internal returns (address cm) {
        _startPrankOrBroadcast(riskCurator);

        // Prepare safe account factory deploy parameters.
        bytes memory constructorParams = abi.encode(
            ap,
            SafeDeployments.SAFE_PROXY_FACTORY_ADDRESS,
            SafeDeployments.SAFE_SINGLETON_ADDRESS,
            SafeDeployments.MULTI_SEND_CALL_ONLY_ADDRESS
        );
        DeployParams memory accountFactoryParams =
            DeployParams({postfix: "SAFE", salt: 0, constructorParams: constructorParams});

        // Set up CreditManager parameters.
        CreditManagerParams memory creditManagerParams = CreditManagerParams({
            maxEnabledTokens: 4,
            feeInterest: 10_00,
            feeLiquidation: 1_50,
            liquidationPremium: 1_50,
            feeLiquidationExpired: 1_50,
            liquidationPremiumExpired: 1_50,
            minDebt: 1e6, // 1e14,
            maxDebt: 25e6, // 1e14 * 25,
            name: "Credit Manager USDC",
            accountFactoryParams: accountFactoryParams
        });
        CreditFacadeParams memory facadeParams =
            CreditFacadeParams({degenNFT: address(0), expirable: false, migrateBotList: false});
        bytes memory creditSuiteParams = abi.encode(creditManagerParams, facadeParams);
        cm = MarketConfigurator(mc).createCreditSuite(3_10, pool, creditSuiteParams);

        _stopPrankOrBroadcast();
        return cm;
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

    /// @dev Configures the pool by setting debt limits, adding tokens, and updating rates.
    function _configurePool(address marketConfigurator, address pool, address cm) internal {
        _startPrankOrBroadcast(riskCurator);

        // Set debt limits
        MarketConfigurator(marketConfigurator).configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTotalDebtLimit, (100e6))
        );
        MarketConfigurator(marketConfigurator).configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setCreditManagerDebtLimit, (cm, 100e6))
        );

        // Set token debt limits
        MarketConfigurator(marketConfigurator).addToken(address(pool), WETH, CHAINLINK_ETH_USD);
        MarketConfigurator(marketConfigurator).addToken(address(pool), USDT, CHAINLINK_USDT_USD);
        MarketConfigurator(marketConfigurator).addToken(address(pool), DAI, CHAINLINK_DAI_USD);

        MarketConfigurator(marketConfigurator).configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTokenLimit, (WETH, 100e6))
        );
        MarketConfigurator(marketConfigurator).configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTokenLimit, (USDT, 100e6))
        );
        MarketConfigurator(marketConfigurator).configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTokenLimit, (DAI, 100e6))
        );
        MarketConfigurator(marketConfigurator).configureRateKeeper(
            address(pool), abi.encodeCall(ITumblerV3.updateRates, ())
        );

        _stopPrankOrBroadcast();

        // address quotaKeeper = IPoolV3(address(ethPool)).poolQuotaKeeper();
        // uint16 quotaRate = IPoolQuotaKeeperV3(quotaKeeper).getQuotaRate(USDC);
        // console.log("quotaRate", quotaRate);
        // ITumblerV3 tumbler = ITumblerV3(IPoolQuotaKeeperV3(quotaKeeper).gauge());
        // address[] memory tokens = new address[](1);
        // tokens[0] = USDC;
        // uint16[] memory rates = tumbler.getRates(tokens);
        // console.log("rates", rates[0]);
    }

    /// @dev Configures the credit suite by adding collateral tokens.
    function _configureCreditSuite(address marketConfigurator, address cm) internal {
        _startPrankOrBroadcast(riskCurator);
        // TODO: uncomment after fixing the issue with CreditConfiguratorV3
        // MarketConfigurator(marketConfigurator).configureCreditSuite(
        //     cm, abi.encodeCall(ICreditConfigureActions.addCollateralToken, (WETH, 1_50))
        // );
        MarketConfigurator(marketConfigurator).configureCreditSuite(
            cm, abi.encodeCall(ICreditConfigureActions.addCollateralToken, (USDT, 1_50))
        );
        MarketConfigurator(marketConfigurator).configureCreditSuite(
            cm, abi.encodeCall(ICreditConfigureActions.addCollateralToken, (DAI, 1_50))
        );
        _stopPrankOrBroadcast();
    }

    /// @dev Deposits funds into the pool and prints liquidity and credit parameters.
    function _depositFunds(address cm, address pool) internal {
        address supplier = makeAddr("SUPPLIER");
        _mintUSDC(supplier, 100e6);

        // vm.deal(supplier, 2e18);
        // IWETH(WETH).deposit{value: 1e18}();

        _startPrankOrBroadcast(supplier);
        IERC20(USDC).approve(address(pool), 100e6);
        IPoolV3(pool).depositWithReferral(100e6, supplier, 0);
        _stopPrankOrBroadcast();

        uint256 availableLiquidity = IPoolV3(pool).availableLiquidity();
        console.log("availableLiquidity", availableLiquidity);
        uint256 debtLimit = IPoolV3(pool).creditManagerDebtLimit(cm);
        console.log("debtLimit", debtLimit);
        uint256 borrowable = IPoolV3(pool).creditManagerBorrowable(cm);
        console.log("borrowable", borrowable);
    }

    /// @dev Increases debt and updates quota using a multicall.
    function _increaseDebtAndUpdateQuota(address creditAccount, CreditFacadeV3_Extension creditFacade) internal {
        _mintWETH(creditAccount, 1e18);
        _mintUSDT(creditAccount, 1e6);
        _mintDAI(creditAccount, 1e18);

        _startPrankOrBroadcast(creditAccount);
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
        _stopPrankOrBroadcast();
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

        _startPrankOrBroadcast(creditAccountOwner);
        safeCreditAccount.execTransaction(
            address(0), 0, "", Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signature
        );
        _stopPrankOrBroadcast();
    }

    // ----------------------------
    // Existing helper functions
    // ----------------------------

    function _setupAccountFactoryAndFacade() internal {
        contractsToUpload.push(
            UploadableContract({
                initCode: type(SafeCreditAccountFactory).creationCode,
                contractType: "ACCOUNT_FACTORY::SAFE",
                version: 3_10
            })
        );

        // Workaround to upload CreditFacadeV3_Extension
        contractsToUpload[24].initCode = type(CreditFacadeV3_Extension).creationCode;

        // contractsToUpload.push(
        //     UploadableContract({
        //         initCode: type(CreditFacadeV3_Extension).creationCode,
        //         contractType: "CREDIT_FACADE",
        //         version: 3_20
        //     })
        // );
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
