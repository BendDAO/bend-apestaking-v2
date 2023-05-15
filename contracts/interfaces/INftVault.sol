// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

import {IApeCoinStaking} from "./IApeCoinStaking.sol";
import {IDelegationRegistry} from "../interfaces/IDelegationRegistry.sol";

interface INftVault is IERC721ReceiverUpgradeable {
    struct NftStatus {
        address owner;
        address staker;
    }

    struct VaultStorage {
        // nft address =>  nft tokenId => nftStatus
        mapping(address => mapping(uint256 => NftStatus)) _nfts;
        // nft address => staker address => refund
        mapping(address => mapping(address => Refund)) _refunds;
        // nft address => staker address => position
        mapping(address => mapping(address => Position)) _positions;
        // nft address => staker address => staking nft tokenId array
        mapping(address => mapping(address => EnumerableSetUpgradeable.UintSet)) _stakingTokenIds;
        IApeCoinStaking apeCoinStaking;
        IERC20Upgradeable apeCoin;
        address bayc;
        address mayc;
        address bakc;
        IDelegationRegistry delegationRegistry;
    }

    struct Refund {
        uint256 principal;
        uint256 reward;
    }
    struct Position {
        uint256 stakedAmount;
        int256 rewardsDebt;
    }

    function stakerOf(address nft_, uint256 tokenId_) external view returns (address);

    function ownerOf(address nft_, uint256 tokenId_) external view returns (address);

    function refundOf(address nft_, address staker_) external view returns (Refund memory);

    function positionOf(address nft_, address staker_) external view returns (Position memory);

    function pendingRewards(address nft_, address staker_) external view returns (uint256);

    function totalStakingNft(address nft_, address staker_) external view returns (uint256);

    function stakingNftIdByIndex(address nft_, address staker_, uint256 index_) external view returns (uint256);

    function isStaking(address nft_, address staker_, uint256 tokenId_) external view returns (bool);

    // delegate.cash

    function setDelegateCash(address delegate_, address nft_, uint256[] calldata tokenIds, bool value) external;

    // deposit nft
    function depositNft(address nft_, uint256[] calldata tokenIds_, address staker_) external;

    // withdraw nft
    function withdrawNft(address nft_, uint256[] calldata tokenIds_) external;

    // staker withdraw ape coin
    function withdrawRefunds(address nft_) external;

    // stake
    function stakeBaycPool(IApeCoinStaking.SingleNft[] calldata nfts_) external;

    function stakeMaycPool(IApeCoinStaking.SingleNft[] calldata nfts_) external;

    function stakeBakcPool(
        IApeCoinStaking.PairNftDepositWithAmount[] calldata baycPairs_,
        IApeCoinStaking.PairNftDepositWithAmount[] calldata maycPairs_
    ) external;

    // unstake
    function unstakeBaycPool(
        IApeCoinStaking.SingleNft[] calldata nfts_,
        address recipient_
    ) external returns (uint256 principal, uint256 rewards);

    function unstakeMaycPool(
        IApeCoinStaking.SingleNft[] calldata nfts_,
        address recipient_
    ) external returns (uint256 principal, uint256 rewards);

    function unstakeBakcPool(
        IApeCoinStaking.PairNftWithdrawWithAmount[] calldata baycPairs_,
        IApeCoinStaking.PairNftWithdrawWithAmount[] calldata maycPairs_,
        address recipient_
    ) external returns (uint256 principal, uint256 rewards);

    // claim rewards
    function claimBaycPool(uint256[] calldata tokenIds_, address recipient_) external returns (uint256 rewards);

    function claimMaycPool(uint256[] calldata tokenIds_, address recipient_) external returns (uint256 rewards);

    function claimBakcPool(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_,
        address recipient_
    ) external returns (uint256 rewards);
}
