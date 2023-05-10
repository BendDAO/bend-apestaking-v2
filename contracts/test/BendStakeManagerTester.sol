// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {BendStakeManager, IApeCoinStaking} from "../BendStakeManager.sol";
import {ApeStakingLib} from "../libraries/ApeStakingLib.sol";

contract BendStakeManagerTester is BendStakeManager {
    function collectFee(uint256 rewardsAmount_) external returns (uint256 feeAmount) {
        return _collectFee(rewardsAmount_);
    }

    function prepareApeCoin(uint256 amount_) external {
        _prepareApeCoin(amount_);
    }

    function distributeRewards(address nft_, uint256 rewardsAmount_) external {
        _distributeRewards(nft_, rewardsAmount_);
    }

    function totalPendingRewardsIncludeFee() external view returns (uint256 amount) {
        amount += _pendingRewards(ApeStakingLib.APE_COIN_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.BAYC_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.MAYC_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.BAKC_POOL_ID);
    }

    function pendingRewardsIncludeFee(uint256 poolId_) external view returns (uint256 amount) {
        amount = _pendingRewards(poolId_);
    }

    function refundOfIncludeFee(address nft_) external view onlyApe(nft_) returns (uint256 amount) {
        (uint256 pricipal, uint256 reward) = _refundOf(nft_);
        amount = pricipal + reward;
    }

    function totalRefundIncludeFee() external view returns (uint256 amount) {
        (uint256 pricipal, uint256 reward) = _totalRefund();
        amount = pricipal + reward;
    }
}
