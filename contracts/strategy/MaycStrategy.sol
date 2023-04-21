// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IRewardsStrategy} from "../interfaces/IRewardsStrategy.sol";

contract MaycStrategy is IRewardsStrategy {
    function calculateNftRewards(uint256 rewardAmount) external pure returns (uint256 nftRewardsAmount) {
        nftRewardsAmount = rewardAmount / 2;
    }
}
