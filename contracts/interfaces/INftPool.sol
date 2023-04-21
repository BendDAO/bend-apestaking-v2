// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;
import {IApeCoinStaking} from "./IApeCoinStaking.sol";
import {IStakeManager} from "./IStakeManager.sol";
import {IStakedNft} from "./IStakedNft.sol";

interface INftPool {
    event RewardDistributed(
        address indexed nft,
        uint256 rewardAmount,
        uint256 stakedNftAmount,
        uint256 accumulatedRewardsPerNft
    );

    event RewardClaimed(address indexed nft, uint256[] indexed tokenIds, address indexed receiver, uint256 amount);

    event NftDeposited(address indexed nft, uint256[] indexed tokenIds, address indexed owner);

    event NftWithdrawn(address indexed nft, uint256[] indexed tokenIds, address indexed owner);

    struct PoolState {
        IStakedNft stakedNft;
        uint256 accumulatedRewardsPerNft;
        mapping(uint256 => uint256) rewardsDebt;
    }

    function staker() external view returns (IStakeManager);

    function claimable(address nft_, uint256[] calldata tokenIds_) external view returns (uint256);

    function deposit(address nft_, uint256[] calldata tokenIds_) external;

    function withdraw(address nft_, uint256[] calldata tokenIds_) external;

    // bacAPE
    function claim(
        address nft_,
        uint256[] calldata tokenIds_,
        address delegateVault_
    ) external;

    // rewards
    function receiveApeCoin(address nft_, uint256 rewardsAmount_) external;
}
