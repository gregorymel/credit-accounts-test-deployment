// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.24;

interface ICreditFacadeV3_Extension {
    function openCreditSmartAccount(address onBehalfOf, address expectedCreditAccount)
        external
        payable
        returns (address creditAccount);
}
