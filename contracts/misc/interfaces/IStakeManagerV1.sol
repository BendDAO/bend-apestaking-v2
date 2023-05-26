// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IStakeManagerV1 {
    function claimFor(address proxy, address staker) external;
}
