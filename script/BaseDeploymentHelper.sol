// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

contract BaseDeploymentHelper {
    // Base contracts & addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address constant CHAINLINK_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant CHAINLINK_USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address constant CHAINLINK_USDT_USD = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    address constant CHAINLINK_DAI_USD = 0x591e79239a7d679378eC8c847e5038150364C78F;

    // fat accounts
    address constant FAT_USDC_HOLDER = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
    address constant FAT_USDT_HOLDER = 0xeE7981C4642dE8d19AeD11dA3bac59277DfD59D7;
    address constant FAT_DAI_HOLDER = 0x0772f014009162efB833eF34d3eA3f243FC735Ba;
}
