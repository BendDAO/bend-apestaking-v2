// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IRewardsStrategy} from "../interfaces/IRewardsStrategy.sol";

abstract contract BaseRewardsStrategy is IRewardsStrategy {
    using Math for uint256;

    uint256 public constant PERCENTAGE_FACTOR = 1e4;

    function getNftRewardsShare() public view virtual returns (uint256 nftShare) {
        nftShare = 5000; // 50%
    }

    function calculateNftRewards(uint256 rewardAmount) public view virtual returns (uint256 nftRewardsAmount) {
        uint256 nftShare = getNftRewardsShare();
        require(nftShare < PERCENTAGE_FACTOR, "BaseRewardsStrategy: nft share is too high");
        nftRewardsAmount = rewardAmount.mulDiv(nftShare, PERCENTAGE_FACTOR, Math.Rounding.Down);
    }
}
