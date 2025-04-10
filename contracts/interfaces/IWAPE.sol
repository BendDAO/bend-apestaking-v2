// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IWAPE {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}
