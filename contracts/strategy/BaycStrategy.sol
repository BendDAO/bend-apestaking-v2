// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IRewardsStrategy} from "../interfaces/IRewardsStrategy.sol";

contract BaycStrategy is IRewardsStrategy {
    function getNftRewardsShare() public pure override returns (uint256 nftShare) {
        nftShare = 7500; // 75%
    }
}
