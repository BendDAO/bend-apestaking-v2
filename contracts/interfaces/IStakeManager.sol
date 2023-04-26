// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;
import {IApeCoinStaking} from "./IApeCoinStaking.sol";
import {IRewardsStrategy} from "./IRewardsStrategy.sol";

interface IStakeManager {
    function apeCoinStaking() external view returns (IApeCoinStaking);

    function totalStakedApeCoin() external view returns (uint256);

    function totalPendingRewards() external view returns (uint256);

    function totalRefund() external view returns (uint256);

    function refundOf(address nft_) external view returns (uint256);

    function stakedApeCoin(uint256 poolId_) external view returns (uint256);

    function pendingRewards(uint256 poolId_) external view returns (uint256);

    function pendingFeeAmount() external view returns (uint256);

    function fee() external view returns (uint256);

    function feeRecipient() external view returns (address);

    function updateFee(uint256 fee_) external;

    function updateFeeRecipient(address recipient_) external;

    //
    function withdrawApeCoin(uint256 required) external returns (uint256);

    // bot
    function updateBotAdmin(address bot_) external;

    // strategy
    function updateRewardsStrategy(address nft_, IRewardsStrategy rewardsStrategy_) external;

    // refund
    function withdrawTotalRefund() external;

    function withdrawRefund(address nft_) external;

    // ape coin pool
    function stakeApeCoin(uint256 amount_) external;

    function unstakeApeCoin(uint256 amount_) external;

    function claimApeCoin() external;

    // bayc pool
    function stakeBayc(uint256[] calldata nfts_) external;

    function unstakeBayc(uint256[] calldata nfts_) external;

    function claimBayc(uint256[] calldata tokenIds_) external;

    // mayc pool
    function stakeMayc(uint256[] calldata nfts_) external;

    function unstakeMayc(uint256[] calldata nfts_) external;

    function claimMayc(uint256[] calldata tokenIds_) external;

    // bakc pool
    function stakeBakc(IApeCoinStaking.PairNft[] calldata baycPairs_, IApeCoinStaking.PairNft[] calldata maycPairs_)
        external;

    function unstakeBakc(IApeCoinStaking.PairNft[] calldata baycPairs_, IApeCoinStaking.PairNft[] calldata maycPairs_)
        external;

    function claimBakc(IApeCoinStaking.PairNft[] calldata baycPairs_, IApeCoinStaking.PairNft[] calldata maycPairs_)
        external;

    struct NftArgs {
        uint256[] bayc;
        uint256[] mayc;
        IApeCoinStaking.PairNft[] baycPairs;
        IApeCoinStaking.PairNft[] maycPairs;
    }

    struct CompoundArgs {
        bool claimCoinPool;
        NftArgs claim;
        NftArgs unstake;
        NftArgs stake;
        uint256 coinStakeThreshold;
    }

    function compound(CompoundArgs calldata args_) external;
}
