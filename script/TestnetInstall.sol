// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

// Forge Std & Testing
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {UploadableContract, GlobalSetup} from "governance/contracts/test/helpers/GlobalSetup.sol";
import {SignatureHelper} from "governance/contracts/test/helpers/SignatureHelper.sol";

// OpenZeppelin
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

// Gearbox Core Interfaces
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IWETH} from "@gearbox-protocol/core-v3/contracts/interfaces/external/IWETH.sol";
import {ITumblerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ITumblerV3.sol";

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
import {CrossChainMultisig} from "governance/contracts/global/CrossChainMultisig.sol";

// Account Management
import {SafeCreditAccountFactory} from "credit-accounts/src/safe/CreditAccountFactory.sol";

// Local Extensions & Utilities
import {CreditFacadeV3_Extension} from "../src/credit/CreditFacadeV3_Extension.sol";

// Helpers
import {CreditAccountHelper} from "../src/CreditAccountHelper.sol";
import {SafeDeployments} from "./helpers/SafeDeploymentLib.sol";
import {AnvilHelper} from "./helpers/AnvilHelper.sol";
import {InstallChecker} from "./InstallChecker.sol";
import {JsonHelper, AddressesJSON, MarketJSON, CreditSuiteJSON} from "./helpers/JsonHelper.sol";
/**
 * @title TestnetInstall
 * @notice This deployment script installs the test market and credit suite on Base.
 */

contract TestnetInstall is GlobalSetup, AnvilHelper, InstallChecker, JsonHelper {
    // State variables
    address internal riskCurator;
    address internal deployer;
    uint256 internal deployerPK;

    address internal GEAR;
    address internal TREASURY;

    string constant name = "Test Market USDC";
    string constant symbol = "dUSDC";

    constructor() GlobalSetup() {
        deployerPK = vm.envUint("DEPLOYER_PRIVATE_KEY");
        console.log("deployerPK", deployerPK);
        deployer = vm.addr(deployerPK);
        riskCurator = vm.addr(_generatePrivateKey("RISK_CURATOR"));
    }

    function runCore() public serializeAddressesJSON {
        if (isAnvil()) {
            console.log("Setting up anvil");
            anvil_setBalance(deployer, 1e18);
            // anvil_impersonateAccount(FAT_USDC_HOLDER);
            // vm.broadcast(FAT_USDC_HOLDER);
            // IERC20(USDC).transfer(deployer, 1e5);
        }

        vm.startBroadcast(deployerPK);

        _setUp();

        // (address pool, address cm) = _createMarket();
        vm.stopBroadcast();

        addressesJSON = AddressesJSON({
            addressProvider: instanceManager.addressProvider(),
            bytecodeRepository: address(bytecodeRepository),
            instanceManager: address(instanceManager),
            multisig: address(multisig)
        });

        // Check that the market is deployed and configured correctly if dry run
        // if (vm.isContext(VmSafe.ForgeContext.ScriptDryRun)) {
        //     _checkProperWork(cm, pool);
        // }
    }

    function runMarket() public loadAddressesJSON serializeMarketJSON {
        instanceManager = InstanceManager(addressesJSON.instanceManager);

        vm.startBroadcast(deployerPK);

        // Retrieve required addresses from the instance manager & address provider.
        address ap = instanceManager.addressProvider();
        address mcf = IAddressProvider(ap).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
        address poolFactory = IAddressProvider(ap).getAddressOrRevert(AP_POOL_FACTORY, 3_10);

        // Fund the pool factory with a minimal USDC deposit.
        _fundPoolFactoryUSDC(poolFactory);

        // Deploy the MarketConfigurator
        address mc = _deployMarketConfigurator(mcf);

        // Deploy and coonfigure pool
        address pool = _deployMarket(mc, ap);
        _configurePool(mc, pool);

        vm.stopBroadcast();

        marketJSON = MarketJSON({marketConfigurator: mc, pool: pool});
    }

    function runCreditSuite() public loadMarketJSON loadAddressesJSON serializeCreditSuiteJSON {
        vm.startBroadcast(deployerPK);

        // Deploy and configure credit suite
        address cm = _deployCreditSuite(marketJSON.marketConfigurator, addressesJSON.addressProvider, marketJSON.pool);
        _configureCreditSuite(marketJSON.marketConfigurator, cm, marketJSON.pool);

        address helper = address(new CreditAccountHelper());

        vm.stopBroadcast();

        console.log("--------------------------------");
        console.log("CreditManager", cm);
        console.log("CreditFacade", ICreditManagerV3(cm).creditFacade());
        console.log("CreditAccountFactory", ICreditManagerV3(cm).accountFactory());
        console.log("CreditAccountHelper", helper);
        console.log("--------------------------------");

        creditSuiteJSON = CreditSuiteJSON({
            creditManager: cm,
            creditFacade: ICreditManagerV3(cm).creditFacade(),
            creditAccountFactory: ICreditManagerV3(cm).accountFactory(),
            creditAccountHelper: helper
        });
    }

    function runUpdateHelper() public loadCreditSuiteJSON serializeCreditSuiteJSON {
        vm.startBroadcast(deployerPK);
        address newCreditAccountHelper = address(new CreditAccountHelper());
        vm.stopBroadcast();

        console.log("--------------------------------");
        console.log("CreditAccountHelper old", creditSuiteJSON.creditAccountHelper);
        console.log("CreditAccountHelper new", newCreditAccountHelper);
        console.log("--------------------------------");

        creditSuiteJSON.creditAccountHelper = newCreditAccountHelper;
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
        _setAccountFactoryAndFacade();
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

    // /**
    //  * @dev Creates and configures the market and credit suite.
    //  */
    // function _createMarket() internal returns (address, address) {
    //     // Retrieve required addresses from the instance manager & address provider.
    //     address ap = instanceManager.addressProvider();
    //     address mcf = IAddressProvider(ap).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
    //     address poolFactory = IAddressProvider(ap).getAddressOrRevert(AP_POOL_FACTORY, 3_10);

    //     // Fund the pool factory with a minimal USDC deposit.
    //     // _fundPoolFactory(poolFactory);
    //     _fundPoolFactoryUSDC(poolFactory);

    //     // Deploy the MarketConfigurator
    //     address mc = _deployMarketConfigurator(mcf);

    //     // Deploy and coonfigure pool
    //     address pool = _deployMarket(mc, ap);
    //     _configurePool(mc, pool);

    //     return (pool, cm);
    // }

    /// @dev Funds the pool factory with a minimal deposit.
    function _fundPoolFactory(address poolFactory) internal {
        IWETH(WETH).deposit{value: 1e5}();
        IERC20(WETH).transfer(poolFactory, 1e5);
    }

    function _fundPoolFactoryUSDC(address poolFactory) internal {
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

        // bytes32 salt = keccak256(abi.encodePacked(deployer, block.timestamp));

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
            minDebt: 1e5, // 1e14,
            maxDebt: 25e5, // 1e14 * 25,
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

    /// @dev Configures the pool by setting debt limits, adding tokens, and updating rates.
    function _configurePool(address marketConfigurator, address pool) internal {
        _startPrankOrBroadcast(riskCurator);

        // Set debt limits
        MarketConfigurator(marketConfigurator).configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setTotalDebtLimit, (100e6))
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
    function _configureCreditSuite(address marketConfigurator, address cm, address pool) internal {
        _startPrankOrBroadcast(riskCurator);
        // TODO: uncomment after fixing the issue with CreditConfiguratorV3
        MarketConfigurator(marketConfigurator).configureCreditSuite(
            cm, abi.encodeCall(ICreditConfigureActions.addCollateralToken, (WETH, 90_00))
        );
        MarketConfigurator(marketConfigurator).configureCreditSuite(
            cm, abi.encodeCall(ICreditConfigureActions.addCollateralToken, (USDT, 90_00))
        );
        MarketConfigurator(marketConfigurator).configureCreditSuite(
            cm, abi.encodeCall(ICreditConfigureActions.addCollateralToken, (DAI, 90_00))
        );

        // set debt limit for credit manager
        MarketConfigurator(marketConfigurator).configurePool(
            address(pool), abi.encodeCall(IPoolConfigureActions.setCreditManagerDebtLimit, (cm, 100e6))
        );

        _stopPrankOrBroadcast();
    }

    // ----------------------------
    // Existing helper functions
    // ----------------------------

    function _setAccountFactoryAndFacade() internal {
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

    function _generatePrivateKey(string memory salt) internal view override(SignatureHelper) returns (uint256) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // uint256 deployerPK = defaultPK;

        // for simplicity, we use the same private key for all accounts
        // deployer == instanceOwner == riskCurator == author == auditor == dao == treasury

        if (
            keccak256(abi.encodePacked(salt)) == keccak256("INSTANCE_OWNER")
                || keccak256(abi.encodePacked(salt)) == keccak256("AUDITOR")
                || keccak256(abi.encodePacked(salt)) == keccak256("AUTHOR")
                || keccak256(abi.encodePacked(salt)) == keccak256("TREASURY")
                || keccak256(abi.encodePacked(salt)) == keccak256("DAO")
                || keccak256(abi.encodePacked(salt)) == keccak256("RISK_CURATOR")
        ) {
            return deployerPrivateKey;
        }

        // These accounts only used for off-chain signatures and don't need to have non-zero balance
        // signer1
        // signer2

        if (keccak256(abi.encodePacked(salt)) == keccak256("SIGNER_1")) {
            return vm.envUint("SIGNER_1_PRIVATE_KEY");
        }

        if (keccak256(abi.encodePacked(salt)) == keccak256("SIGNER_2")) {
            return vm.envUint("SIGNER_2_PRIVATE_KEY");
        }

        console.log("Generating private key for...", salt);
        return uint256(keccak256(abi.encodePacked(salt)));
    }
}
