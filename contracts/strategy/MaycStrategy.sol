// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {BaseRewardsStrategy} from "./BaseRewardsStrategy.sol";

contract MaycStrategy is BaseRewardsStrategy {
    function getNftRewardsShare() public pure override returns (uint256 nftShare) {
        nftShare = 7000; // 70%
    }
}
