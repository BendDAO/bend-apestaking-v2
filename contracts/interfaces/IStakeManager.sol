// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;
import {IApeCoinStaking} from "./IApeCoinStaking.sol";
import {IRewardsStrategy} from "./IRewardsStrategy.sol";
import {IStakedNft} from "./IStakedNft.sol";

interface IStakeManager {
    function stBayc() external view returns (IStakedNft);

    function stMayc() external view returns (IStakedNft);

    function stBakc() external view returns (IStakedNft);

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

    // bot
    function updateBotAdmin(address bot_) external;

    // strategy
    function updateRewardsStrategy(address nft_, IRewardsStrategy rewardsStrategy_) external;

    function withdrawApeCoin(uint256 required) external returns (uint256);

    function mintStNft(IStakedNft stNft_, address to_, uint256[] memory tokenIds_) external;

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
