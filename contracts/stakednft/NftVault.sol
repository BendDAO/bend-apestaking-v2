// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {INftVault, IApeCoinStaking, IERC721ReceiverUpgradeable, IDelegateRegistryV2} from "../interfaces/INftVault.sol";
import {IDelegationRegistry} from "../interfaces/IDelegationRegistry.sol";

import {ApeStakingLib} from "../libraries/ApeStakingLib.sol";
import {VaultLogic} from "./VaultLogic.sol";
import {IWAPE} from "../interfaces/IWAPE.sol";

contract NftVault is INftVault, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using ApeStakingLib for IApeCoinStaking;

    VaultStorage internal _vaultStorage;

    modifier onlyApe(address nft_) {
        require(
            nft_ == _vaultStorage.bayc || nft_ == _vaultStorage.mayc || nft_ == _vaultStorage.bakc,
            "NftVault: not ape"
        );
        _;
    }

    modifier onlyApeCaller() {
        require(
            msg.sender == _vaultStorage.bayc || msg.sender == _vaultStorage.mayc || msg.sender == _vaultStorage.bakc,
            "NftVault: caller not ape"
        );
        _;
    }

    modifier onlyAuthorized() {
        require(_vaultStorage.authorized[msg.sender], "StNft: caller is not authorized");
        _;
    }

    function initialize(
        address wrapApeCoin_,
        IApeCoinStaking apeCoinStaking_,
        IDelegationRegistry delegationRegistry_
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        _vaultStorage.apeCoinStaking = apeCoinStaking_;
        _vaultStorage.delegationRegistry = delegationRegistry_;
        _vaultStorage.wrapApeCoin = IERC20Upgradeable(wrapApeCoin_);
        _vaultStorage.bayc = address(_vaultStorage.apeCoinStaking.bayc());
        _vaultStorage.mayc = address(_vaultStorage.apeCoinStaking.mayc());
        _vaultStorage.bakc = address(_vaultStorage.apeCoinStaking.bakc());
        _vaultStorage.wrapApeCoin.approve(address(_vaultStorage.apeCoinStaking), type(uint256).max);
    }

    receive() external payable {
        require(
            (msg.sender == address(_vaultStorage.wrapApeCoin)) || (msg.sender == address(_vaultStorage.apeCoinStaking)),
            "nftVault: invalid sender"
        );
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view override onlyApeCaller returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function stakerOf(address nft_, uint256 tokenId_) external view onlyApe(nft_) returns (address) {
        return VaultLogic._stakerOf(_vaultStorage, nft_, tokenId_);
    }

    function ownerOf(address nft_, uint256 tokenId_) external view onlyApe(nft_) returns (address) {
        return VaultLogic._ownerOf(_vaultStorage, nft_, tokenId_);
    }

    function refundOf(address nft_, address staker_) external view onlyApe(nft_) returns (Refund memory) {
        return _vaultStorage.refunds[nft_][staker_];
    }

    function positionOf(address nft_, address staker_) external view onlyApe(nft_) returns (Position memory) {
        return _vaultStorage.positions[nft_][staker_];
    }

    function pendingRewards(address nft_, address staker_) external view onlyApe(nft_) returns (uint256) {
        IApeCoinStaking.PoolWithoutTimeRange memory pool = _vaultStorage.apeCoinStaking.getNftPool(nft_);
        Position memory position = _vaultStorage.positions[nft_][staker_];

        (uint256 rewardsSinceLastCalculated, ) = _vaultStorage.apeCoinStaking.getNftRewardsBy(
            nft_,
            pool.lastRewardedTimestampHour,
            ApeStakingLib.getPreviousTimestampHour()
        );
        uint256 accumulatedRewardsPerShare = pool.accumulatedRewardsPerShare;

        if (
            block.timestamp > pool.lastRewardedTimestampHour + ApeStakingLib.SECONDS_PER_HOUR && pool.stakedAmount != 0
        ) {
            accumulatedRewardsPerShare =
                accumulatedRewardsPerShare +
                (rewardsSinceLastCalculated * ApeStakingLib.APE_COIN_PRECISION) /
                pool.stakedAmount;
        }
        return
            uint256(int256(position.stakedAmount * accumulatedRewardsPerShare) - position.rewardsDebt) /
            ApeStakingLib.APE_COIN_PRECISION;
    }

    function totalStakingNft(address nft_, address staker_) external view returns (uint256) {
        return _vaultStorage.stakingTokenIds[nft_][staker_].length();
    }

    function stakingNftIdByIndex(address nft_, address staker_, uint256 index_) external view returns (uint256) {
        return _vaultStorage.stakingTokenIds[nft_][staker_].at(index_);
    }

    function isStaking(address nft_, address staker_, uint256 tokenId_) external view returns (bool) {
        return _vaultStorage.stakingTokenIds[nft_][staker_].contains(tokenId_);
    }

    function authorise(address addr_, bool authorized_) external override onlyOwner {
        _vaultStorage.authorized[addr_] = authorized_;
    }

    function setDelegateCash(
        address delegate_,
        address nft_,
        uint256[] calldata tokenIds_,
        bool value_
    ) external override onlyAuthorized onlyApe(nft_) {
        require(delegate_ != address(0), "nftVault: invalid delegate");
        uint256 tokenId_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            require(
                msg.sender == VaultLogic._ownerOf(_vaultStorage, nft_, tokenId_),
                "nftVault: only owner can delegate"
            );
            _vaultStorage.delegationRegistry.delegateForToken(delegate_, nft_, tokenId_, value_);
        }
    }

    function getDelegateCashForToken(
        address nft_,
        uint256[] calldata tokenIds_
    ) external view override returns (address[][] memory delegates) {
        delegates = new address[][](tokenIds_.length);
        uint256 tokenId_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            delegates[i] = _vaultStorage.delegationRegistry.getDelegatesForToken(address(this), nft_, tokenId_);
        }
    }

    function setDelegationRegistryV2Contract(address registryV2_) external onlyOwner {
        _vaultStorage.delegationRegistryV2 = IDelegateRegistryV2(registryV2_);
    }

    function setDelegateCashV2(
        address delegate_,
        address nft_,
        uint256[] calldata tokenIds_,
        bool value_
    ) external override onlyAuthorized onlyApe(nft_) {
        require(delegate_ != address(0), "nftVault: invalid delegate");
        uint256 tokenId_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            require(
                msg.sender == VaultLogic._ownerOf(_vaultStorage, nft_, tokenId_),
                "nftVault: only owner can delegate"
            );
            _vaultStorage.delegationRegistryV2.delegateERC721(delegate_, nft_, tokenId_, "", value_);
        }
    }

    function getDelegateCashForTokenV2(
        address nft_,
        uint256[] calldata tokenIds_
    ) external view override returns (address[][] memory delegates) {
        IDelegateRegistryV2.Delegation[] memory allDelegations = _vaultStorage
            .delegationRegistryV2
            .getOutgoingDelegations(address(this));

        delegates = new address[][](tokenIds_.length);
        uint256 tokenId_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];

            uint256 tokenDelegatesNum;
            for (uint256 j = 0; j < allDelegations.length; j++) {
                if (allDelegations[j].contract_ == nft_ && allDelegations[j].tokenId == tokenId_) {
                    tokenDelegatesNum++;
                }
            }

            delegates[i] = new address[](tokenDelegatesNum);
            uint256 tokenDelegateIdx;
            for (uint256 j = 0; j < allDelegations.length; j++) {
                if (allDelegations[j].contract_ == nft_ && allDelegations[j].tokenId == tokenId_) {
                    delegates[i][tokenDelegateIdx] = allDelegations[j].to;
                    tokenDelegateIdx++;
                }
            }
        }
    }

    function depositNft(
        address nft_,
        uint256[] calldata tokenIds_,
        address staker_
    ) external override onlyApe(nft_) onlyAuthorized nonReentrant {
        uint256 tokenId_;
        IApeCoinStaking.Position memory position_;

        // transfer nft and set permission
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            // block partially stake from official contract
            tokenId_ = tokenIds_[i];
            position_ = _vaultStorage.apeCoinStaking.getNftPosition(nft_, tokenId_);
            require(position_.stakedAmount == 0, "nftVault: nft already staked");

            IERC721Upgradeable(nft_).safeTransferFrom(msg.sender, address(this), tokenIds_[i]);
            _vaultStorage.nfts[nft_][tokenIds_[i]] = NftStatus(msg.sender, staker_);
        }
        emit NftDeposited(nft_, msg.sender, staker_, tokenIds_);
    }

    function withdrawNft(
        address nft_,
        uint256[] calldata tokenIds_
    ) external override onlyApe(nft_) onlyAuthorized nonReentrant {
        require(tokenIds_.length > 0, "nftVault: invalid tokenIds");
        address staker_ = VaultLogic._stakerOf(_vaultStorage, nft_, tokenIds_[0]);

        VaultLogic._refundSinglePool(_vaultStorage, nft_, tokenIds_);

        // transfer nft to sender
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            require(
                msg.sender == VaultLogic._ownerOf(_vaultStorage, nft_, tokenIds_[i]),
                "nftVault: caller must be nft owner"
            );
            require(
                staker_ == VaultLogic._stakerOf(_vaultStorage, nft_, tokenIds_[i]),
                "nftVault: staker must be same"
            );
            delete _vaultStorage.nfts[nft_][tokenIds_[i]];
            // transfer nft
            IERC721Upgradeable(nft_).safeTransferFrom(address(this), msg.sender, tokenIds_[i]);
        }
        emit NftWithdrawn(nft_, msg.sender, staker_, tokenIds_);
    }

    function withdrawRefunds(address nft_) external override onlyApe(nft_) onlyAuthorized nonReentrant {
        Refund memory _refund = _vaultStorage.refunds[nft_][msg.sender];
        uint256 amount = _refund.principal + _refund.reward;
        delete _vaultStorage.refunds[nft_][msg.sender];
        _vaultStorage.wrapApeCoin.transfer(msg.sender, amount);
    }

    function _stakeNft(
        uint256 poolId_,
        address nft_,
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_
    ) internal {
        uint256 totalStakedAmount = 0;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            require(
                msg.sender == VaultLogic._stakerOf(_vaultStorage, nft_, tokenIds_[i]),
                "nftVault: caller must be nft staker"
            );
            totalStakedAmount += amounts_[i];
            _vaultStorage.stakingTokenIds[nft_][msg.sender].add(tokenIds_[i]);
        }

        // unwrap ape coin, and deposit nft into staking
        _vaultStorage.wrapApeCoin.transferFrom(msg.sender, address(this), totalStakedAmount);
        IWAPE(address(_vaultStorage.wrapApeCoin)).withdraw(totalStakedAmount);

        _vaultStorage.apeCoinStaking.deposit{value: totalStakedAmount}(poolId_, tokenIds_, amounts_);

        VaultLogic._increasePosition(_vaultStorage, nft_, msg.sender, totalStakedAmount);

        emit SingleNftStaked(nft_, msg.sender, tokenIds_, amounts_);
    }

    function _unstakeNft(
        uint256 poolId_,
        address nft_,
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_,
        address recipient_
    ) internal returns (uint256 principal, uint256 rewards) {
        IApeCoinStaking.Position memory position_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            require(
                msg.sender == VaultLogic._stakerOf(_vaultStorage, nft_, tokenIds_[i]),
                "nftVault: caller must be nft staker"
            );
            principal += amounts_[i];
            position_ = _vaultStorage.apeCoinStaking.getNftPosition(nft_, tokenIds_[i]);
            if (position_.stakedAmount == amounts_[i]) {
                _vaultStorage.stakingTokenIds[nft_][msg.sender].remove(tokenIds_[i]);
            }
        }

        rewards = _vaultStorage.wrapApeCoin.balanceOf(recipient_);

        // withdraw nft from staking, and wrap ape coin
        _vaultStorage.apeCoinStaking.withdraw(poolId_, tokenIds_, amounts_, address(this));

        uint256 nativeBalance = address(this).balance;
        IWAPE(address(_vaultStorage.wrapApeCoin)).deposit{value: nativeBalance}();
        IERC20Upgradeable(address(_vaultStorage.wrapApeCoin)).transfer(recipient_, nativeBalance);

        rewards = _vaultStorage.wrapApeCoin.balanceOf(recipient_) - rewards - principal;
        if (rewards > 0) {
            VaultLogic._updateRewardsDebt(_vaultStorage, nft_, msg.sender, rewards);
        }

        VaultLogic._decreasePosition(_vaultStorage, nft_, msg.sender, principal);

        emit SingleNftUnstaked(nft_, msg.sender, tokenIds_, amounts_);
    }

    function _claimNft(
        uint256 poolId_,
        address nft_,
        uint256[] calldata tokenIds_,
        address recipient_
    ) internal returns (uint256 rewards) {
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            require(
                msg.sender == VaultLogic._stakerOf(_vaultStorage, nft_, tokenIds_[i]),
                "nftVault: caller must be nft staker"
            );
        }

        rewards = _vaultStorage.wrapApeCoin.balanceOf(address(recipient_));

        // claim rewards from staking, and wrap ape coin
        _vaultStorage.apeCoinStaking.claim(poolId_, tokenIds_, address(this));

        uint256 nativeBalance = address(this).balance;
        IWAPE(address(_vaultStorage.wrapApeCoin)).deposit{value: nativeBalance}();
        IERC20Upgradeable(address(_vaultStorage.wrapApeCoin)).transfer(recipient_, nativeBalance);

        rewards = _vaultStorage.wrapApeCoin.balanceOf(recipient_) - rewards;
        if (rewards > 0) {
            VaultLogic._updateRewardsDebt(_vaultStorage, nft_, msg.sender, rewards);
        }

        emit SingleNftClaimed(nft_, msg.sender, tokenIds_, rewards);
    }

    // BAYC

    function stakeBaycPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_
    ) external override onlyAuthorized nonReentrant {
        _stakeNft(ApeStakingLib.BAYC_POOL_ID, _vaultStorage.bayc, tokenIds_, amounts_);
    }

    function unstakeBaycPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_,
        address recipient_
    ) external override onlyAuthorized nonReentrant returns (uint256 principal, uint256 rewards) {
        return _unstakeNft(ApeStakingLib.BAYC_POOL_ID, _vaultStorage.bayc, tokenIds_, amounts_, recipient_);
    }

    function claimBaycPool(
        uint256[] calldata tokenIds_,
        address recipient_
    ) external override onlyAuthorized nonReentrant returns (uint256 rewards) {
        return _claimNft(ApeStakingLib.BAYC_POOL_ID, _vaultStorage.bayc, tokenIds_, recipient_);
    }

    // MAYC

    function stakeMaycPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_
    ) external override onlyAuthorized nonReentrant {
        _stakeNft(ApeStakingLib.MAYC_POOL_ID, _vaultStorage.mayc, tokenIds_, amounts_);
    }

    function unstakeMaycPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_,
        address recipient_
    ) external override onlyAuthorized nonReentrant returns (uint256 principal, uint256 rewards) {
        return _unstakeNft(ApeStakingLib.MAYC_POOL_ID, _vaultStorage.mayc, tokenIds_, amounts_, recipient_);
    }

    function claimMaycPool(
        uint256[] calldata tokenIds_,
        address recipient_
    ) external override onlyAuthorized nonReentrant returns (uint256 rewards) {
        return _claimNft(ApeStakingLib.MAYC_POOL_ID, _vaultStorage.mayc, tokenIds_, recipient_);
    }

    // BAKC

    function stakeBakcPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_
    ) external override onlyAuthorized nonReentrant {
        _stakeNft(ApeStakingLib.BAKC_POOL_ID, _vaultStorage.bakc, tokenIds_, amounts_);
    }

    function unstakeBakcPool(
        uint256[] calldata tokenIds_,
        uint256[] calldata amounts_,
        address recipient_
    ) external override onlyAuthorized nonReentrant returns (uint256 principal, uint256 rewards) {
        return _unstakeNft(ApeStakingLib.BAKC_POOL_ID, _vaultStorage.bakc, tokenIds_, amounts_, recipient_);
    }

    function claimBakcPool(
        uint256[] calldata tokenIds_,
        address recipient_
    ) external override onlyAuthorized nonReentrant returns (uint256 rewards) {
        return _claimNft(ApeStakingLib.BAKC_POOL_ID, _vaultStorage.bakc, tokenIds_, recipient_);
    }
}
