// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {INftVault} from "./interfaces/INftVault.sol";
import {IStakeManager} from "./interfaces/IStakeManager.sol";
import {INftPool, IStakedNft, IApeCoinStaking} from "./interfaces/INftPool.sol";
import {ICoinPool} from "./interfaces/ICoinPool.sol";
import {IDelegationRegistry} from "./interfaces/IDelegationRegistry.sol";

import {ApeStakingLib} from "./libraries/ApeStakingLib.sol";

contract BendNftPool is INftPool, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for ICoinPool;
    using ApeStakingLib for IApeCoinStaking;

    uint256 private constant APE_COIN_PRECISION = 1e18;

    IApeCoinStaking public apeCoinStaking;
    IERC20Upgradeable public apeCoin;
    mapping(address => PoolState) public poolStates;
    IStakeManager public override staker;
    ICoinPool public coinPool;
    IDelegationRegistry public delegation;
    address public bayc;
    address public mayc;
    address public bakc;

    modifier onlyApe(address nft_) {
        require(bayc == nft_ || mayc == nft_ || bakc == nft_, "BendNftPool: not ape");
        _;
    }

    modifier onlyStaker() {
        require(_msgSender() == address(staker), "BendNftPool: caller is not staker");
        _;
    }

    function initialize(
        IApeCoinStaking apeStaking_,
        IDelegationRegistry delegation_,
        ICoinPool coinPool_,
        IStakeManager staker_,
        IStakedNft stBayc,
        IStakedNft stMayc,
        IStakedNft stBakc
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        apeCoinStaking = apeStaking_;

        staker = staker_;
        coinPool = coinPool_;
        delegation = delegation_;

        bayc = stBayc.underlyingAsset();
        mayc = stMayc.underlyingAsset();
        bakc = stBakc.underlyingAsset();
        poolStates[bayc].stakedNft = stBayc;
        poolStates[mayc].stakedNft = stMayc;
        poolStates[bakc].stakedNft = stBakc;

        IERC721Upgradeable(bayc).setApprovalForAll(address(stBayc), true);
        IERC721Upgradeable(mayc).setApprovalForAll(address(stMayc), true);
        IERC721Upgradeable(bakc).setApprovalForAll(address(stBakc), true);

        apeCoin = IERC20Upgradeable(apeCoinStaking.apeCoin());
        apeCoin.approve(address(coinPool), type(uint256).max);
    }

    function deposit(address nft_, uint256[] calldata tokenIds_) external override onlyApe(nft_) {
        PoolState storage pool = poolStates[nft_];

        uint256 tokenId_;

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            IERC721Upgradeable(nft_).safeTransferFrom(_msgSender(), address(this), tokenId_);

            pool.rewardsDebt[tokenId_] = pool.accumulatedRewardsPerNft;
        }

        pool.stakedNft.mint(address(staker), _msgSender(), tokenIds_);

        emit NftDeposited(nft_, tokenIds_, _msgSender());
    }

    function withdraw(address nft_, uint256[] calldata tokenIds_) external override onlyApe(nft_) {
        _claim(_msgSender(), _msgSender(), nft_, tokenIds_);

        PoolState storage pool = poolStates[nft_];

        uint256 tokenId_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            pool.stakedNft.safeTransferFrom(_msgSender(), address(this), tokenId_);
        }

        pool.stakedNft.burn(tokenIds_);

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            IERC721Upgradeable(pool.stakedNft.underlyingAsset()).safeTransferFrom(
                address(this),
                _msgSender(),
                tokenId_
            );
            delete pool.rewardsDebt[tokenId_];
        }

        emit NftWithdrawn(nft_, tokenIds_, _msgSender());
    }

    function _claim(
        address owner_,
        address receiver_,
        address nft_,
        uint256[] calldata tokenIds_
    ) internal {
        PoolState storage pool = poolStates[nft_];
        uint256 tokenId_;
        uint256 claimableRewards;

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            require(
                pool.stakedNft.ownerOf(tokenId_) == owner_ &&
                    pool.stakedNft.minterOf(tokenId_) == address(this) &&
                    pool.stakedNft.stakerOf(tokenId_) == address(staker),
                "BendNftPool: invalid token id"
            );

            if (pool.accumulatedRewardsPerNft > pool.rewardsDebt[tokenId_]) {
                claimableRewards += _round_claimble_rewards(pool.accumulatedRewardsPerNft, pool.rewardsDebt[tokenId_]);
                pool.rewardsDebt[tokenId_] = pool.accumulatedRewardsPerNft;
            }
        }

        if (claimableRewards > 0) {
            coinPool.withdraw(claimableRewards, receiver_, address(this));
            emit RewardClaimed(nft_, tokenIds_, receiver_, claimableRewards);
        }
    }

    function claim(
        address nft_,
        uint256[] calldata tokenIds_,
        address delegateVault_
    ) external override onlyApe(nft_) {
        address owner = _msgSender();
        address receiver = _msgSender();
        if (delegateVault_ != address(0)) {
            uint256 tokenId_;
            for (uint256 i = 0; i < tokenIds_.length; i++) {
                tokenId_ = tokenIds_[i];
                PoolState storage pool = poolStates[nft_];
                bool isDelegateValid = delegation.checkDelegateForToken(
                    msg.sender,
                    delegateVault_,
                    address(pool.stakedNft),
                    tokenId_
                );
                require(isDelegateValid, "BendNftPool: invalid delegate-vault pairing");
            }

            owner = delegateVault_;
        }
        _claim(owner, receiver, nft_, tokenIds_);
    }

    function receiveApeCoin(address nft_, uint256 rewardsAmount_) external override onlyApe(nft_) onlyStaker {
        IERC20Upgradeable(apeCoin).safeTransferFrom(_msgSender(), address(this), rewardsAmount_);

        PoolState storage pool = poolStates[nft_];
        pool.accumulatedRewardsPerNft += ((rewardsAmount_ * APE_COIN_PRECISION) /
            pool.stakedNft.totalStaked(address(staker)));

        coinPool.deposit(rewardsAmount_, address(this));

        emit RewardDistributed(
            nft_,
            rewardsAmount_,
            pool.stakedNft.totalStaked(address(staker)),
            pool.accumulatedRewardsPerNft
        );
    }

    function claimable(address nft_, uint256[] calldata tokenIds_)
        external
        view
        override
        onlyApe(nft_)
        returns (uint256 amount)
    {
        PoolState storage pool = poolStates[nft_];
        uint256 tokenId_ = 0;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            if (pool.accumulatedRewardsPerNft > pool.rewardsDebt[tokenId_]) {
                amount += _round_claimble_rewards(pool.accumulatedRewardsPerNft, pool.rewardsDebt[tokenId_]);
            }
        }
    }

    function getPoolStateUI(address nft_)
        external
        view
        returns (uint256 totalNftAmount, uint256 accumulatedRewardsPerNft)
    {
        PoolState storage pool = poolStates[nft_];
        totalNftAmount = pool.stakedNft.totalSupply();
        accumulatedRewardsPerNft = pool.accumulatedRewardsPerNft;
    }

    function getNftStateUI(address nft_, uint256 tokenId) external view returns (uint256 rewardsDebt) {
        PoolState storage pool = poolStates[nft_];
        rewardsDebt = pool.rewardsDebt[tokenId];
    }

    function onERC721Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*tokenId*/
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        bool isValidNFT = (bayc == msg.sender || mayc == msg.sender || bakc == msg.sender);
        if (!isValidNFT) {
            isValidNFT = (address(poolStates[bayc].stakedNft) == msg.sender ||
                address(poolStates[mayc].stakedNft) == msg.sender ||
                address(poolStates[bakc].stakedNft) == msg.sender);
        }
        require(isValidNFT, "BendNftPool: not ape nft");
        return this.onERC721Received.selector;
    }

    /*
     * @dev Rounds down the claimable rewards to the nearest integer.
     * Because ERC4626 will round down the rewards when withdraw.
     */
    function _round_claimble_rewards(uint256 accumulatedRewardsPerNft, uint256 rewardsDebt)
        private
        pure
        returns (uint256 rewards)
    {
        rewards = (accumulatedRewardsPerNft - rewardsDebt) / APE_COIN_PRECISION;
        if (rewards > 0) {
            rewards -= 1;
        }
    }
}
