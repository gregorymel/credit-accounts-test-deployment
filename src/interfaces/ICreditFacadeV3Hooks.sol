// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.24;

interface ICreditFacadeV3Hooks {
    function preExecutionCheck() external;
    function postExecutionCheck() external;
    function getOpenCreditAccountContextOrRevert() external view returns (address);
}
