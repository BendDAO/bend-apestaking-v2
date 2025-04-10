// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

import {IApeCoinStaking} from "./IApeCoinStaking.sol";
import {IDelegationRegistry} from "../interfaces/IDelegationRegistry.sol";
import {IDelegateRegistryV2} from "../interfaces/IDelegateRegistryV2.sol";

interface INftVault is IERC721ReceiverUpgradeable {
    event NftDeposited(address indexed nft, address indexed owner, address indexed staker, uint256[] tokenIds);
    event NftWithdrawn(address indexed nft, address indexed owner, address indexed staker, uint256[] tokenIds);

    event SingleNftStaked(address indexed nft, address indexed staker, uint256[] tokenIds, uint256[] amounts);
    event SingleNftUnstaked(address indexed nft, address indexed staker, uint256[] tokenIds, uint256[] amounts);

    event SingleNftClaimed(address indexed nft, address indexed staker, uint256[] tokenIds, uint256 rewards);

    struct NftStatus {
        address owner;
        address staker;
    }

    struct VaultStorage {
        // nft address =>  nft tokenId => nftStatus
        mapping(address => mapping(uint256 => NftStatus)) nfts;
        // nft address => staker address => refund
        mapping(address => mapping(address => Refund)) refunds;
        // nft address => staker address => position
        mapping(address => mapping(address => Position)) positions;
        // nft address => staker address => staking nft tokenId array
        mapping(address => mapping(address => EnumerableSetUpgradeable.UintSet)) stakingTokenIds;
        IApeCoinStaking apeCoinStaking;
        IERC20Upgradeable wrapApeCoin;
        address bayc;
        address mayc;
        address bakc;
        IDelegationRegistry delegationRegistry;
        mapping(address => bool) authorized;
        IDelegateRegistryV2 delegationRegistryV2;
    }

    struct Refund {
        uint256 principal;
        uint256 reward;
    }
    struct Position {
        uint256 stakedAmount;
        int256 rewardsDebt;
    }

    function authorise(address addr_, bool authorized_) external;

    function stakerOf(address nft_, uint256 tokenId_) external view returns (address);

    function ownerOf(address nft_, uint256 tokenId_) external view returns (address);

    function refundOf(address nft_, address staker_) external view returns (Refund memory);

    function positionOf(address nft_, address staker_) external view returns (Position memory);

    function pendingRewards(address nft_, address staker_) external view returns (uint256);

    function totalStakingNft(address nft_, address staker_) external view returns (uint256);

    function stakingNftIdByIndex(address nft_, address staker_, uint256 index_) external view returns (uint256);

    function isStaking(address nft_, address staker_, uint256 tokenId_) external view returns (bool);

    // delegate.cash V1

    function setDelegateCash(address delegate_, address nft_, uint256[] calldata tokenIds, bool value) external;

    function getDelegateCashForToken(
        address nft_,
        uint256[] calldata tokenIds_
    ) external view returns (address[][] memory);

    // delegate.cash V2

    function setDelegateCashV2(address delegate_, address nft_, uint256[] calldata tokenIds, bool value) external;

    function getDelegateCashForTokenV2(
        address nft_,
        uint256[] calldata tokenIds_
    ) external view returns (address[][] memory);

    // deposit nft
    function depositNft(address nft_, uint256[] calldata tokenIds_, address staker_) external;

    // withdraw nft
    function withdrawNft(address nft_, uint256[] calldata tokenIds_) external;

    // staker withdraw ape coin
    function withdrawRefunds(address nft_) external;

    // stake
    function stakeBaycPool(uint256[] calldata tokenIds_, uint256[] calldata amounts_) external;

    function stakeMaycPool(uint256[] calldata tokenIds_, uint256[] calldata amounts_) external;

    function stakeBakcPool(uint256[] calldata tokenIds_, uint256[] calldata amounts_) external;

    // unstake
    function unstakeBaycPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_,
        address recipient_
    ) external returns (uint256 principal, uint256 rewards);

    function unstakeMaycPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_,
        address recipient_
    ) external returns (uint256 principal, uint256 rewards);

    function unstakeBakcPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_,
        address recipient_
    ) external returns (uint256 principal, uint256 rewards);

    // claim rewards
    function claimBaycPool(uint256[] calldata tokenIds_, address recipient_) external returns (uint256 rewards);

    function claimMaycPool(uint256[] calldata tokenIds_, address recipient_) external returns (uint256 rewards);

    function claimBakcPool(uint256[] calldata tokenIds_, address recipient_) external returns (uint256 rewards);
}
