// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IApeCoinStaking} from "../interfaces/IApeCoinStaking.sol";
import {INftVault} from "../interfaces/INftVault.sol";
import {ICoinPool} from "../interfaces/ICoinPool.sol";
import {INftPool} from "../interfaces/INftPool.sol";
import {IStakeManager} from "../interfaces/IStakeManager.sol";
import {IWithdrawStrategy} from "../interfaces/IWithdrawStrategy.sol";
import {IPoolViewer} from "./interfaces/IPoolViewer.sol";

import {ApeStakingLib} from "../libraries/ApeStakingLib.sol";

contract PoolViewer is IPoolViewer {
    using ApeStakingLib for IApeCoinStaking;
    IApeCoinStaking public immutable apeCoinStaking;
    IStakeManager public immutable staker;
    ICoinPool public immutable coinPool;

    address public immutable bayc;
    address public immutable mayc;
    address public immutable bakc;

    constructor(IApeCoinStaking apeCoinStaking_, ICoinPool coinPool_, IStakeManager staker_) {
        apeCoinStaking = apeCoinStaking_;
        coinPool = coinPool_;
        staker = staker_;

        bayc = address(apeCoinStaking.bayc());
        mayc = address(apeCoinStaking.mayc());
        bakc = address(apeCoinStaking.bakc());
    }

    function viewPool() external view returns (PoolState memory poolState) {
        poolState.coinPoolPendingApeCoin = coinPool.pendingApeCoin();
        poolState.coinPoolPendingRewards = staker.pendingRewards(0);
        poolState.coinPoolStakedAmount = staker.stakedApeCoin(0);
        poolState.baycPoolMaxCap = apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAYC_POOL_ID).capPerPosition;
        poolState.maycPoolMaxCap = apeCoinStaking.getCurrentTimeRange(ApeStakingLib.MAYC_POOL_ID).capPerPosition;
        poolState.bakcPoolMaxCap = apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAKC_POOL_ID).capPerPosition;
    }

    function viewNftPoolPendingRewards(
        address nft_,
        uint256[] calldata tokenIds_
    ) external view returns (uint256 rewards) {
        uint256 poolId = apeCoinStaking.getNftPoolId(nft_);
        uint256 reward;
        for (uint256 i; i < tokenIds_.length; i++) {
            reward = apeCoinStaking.pendingRewards(poolId, address(0), tokenIds_[i]);
            reward -= staker.calculateFee(reward);
            rewards += reward;
        }
    }
}
