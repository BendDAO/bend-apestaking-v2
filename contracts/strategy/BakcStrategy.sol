// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {DefaultRewardsStrategy} from "./DefaultRewardsStrategy.sol";

contract BakcStrategy is DefaultRewardsStrategy {
    constructor(uint256 nftShare_) DefaultRewardsStrategy(nftShare_) {}
}
