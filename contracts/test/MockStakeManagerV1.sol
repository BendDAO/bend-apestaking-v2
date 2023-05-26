// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStakeManagerV1} from "../misc/interfaces/IStakeManagerV1.sol";

contract MockStakeManagerV1 is IStakeManagerV1 {
    uint256 public constant REWARDS_AMOUNT = 100 * 1e18;

    IERC20 public apeCoin;

    constructor(address apeCoin_) {
        apeCoin = IERC20(apeCoin_);
    }

    function claimFor(address proxy, address staker) external override {
        proxy;

        apeCoin.transfer(staker, REWARDS_AMOUNT);
    }
}
