// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IStakeManager, IApeCoinStaking} from "./interfaces/IStakeManager.sol";
import {INftVault} from "./interfaces/INftVault.sol";
import {ICoinPool} from "./interfaces/ICoinPool.sol";
import {INftPool} from "./interfaces/INftPool.sol";
import {IStakedNft} from "./interfaces/IStakedNft.sol";
import {IRewardsStrategy} from "./interfaces/IRewardsStrategy.sol";
import {IWithdrawStrategy} from "./interfaces/IWithdrawStrategy.sol";

import {ApeStakingLib} from "./libraries/ApeStakingLib.sol";

contract BendStakeManager is IStakeManager, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using ApeStakingLib for IApeCoinStaking;
    using MathUpgradeable for uint256;

    uint256 public constant PERCENTAGE_FACTOR = 1e4;
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant MAX_PENDING_FEE = 100 * 1e18;

    struct StakerStorage {
        mapping(address => IRewardsStrategy) rewardsStrategies;
        IWithdrawStrategy withdrawStrategy;
        uint256 fee;
        address feeRecipient;
        uint256 pendingFeeAmount;
        uint256 apeCoinPoolStakedAmount;
        IApeCoinStaking apeCoinStaking;
        IERC20Upgradeable apeCoin;
        INftVault nftVault;
        ICoinPool coinPool;
        INftPool nftPool;
        IStakedNft stBayc;
        IStakedNft stMayc;
        IStakedNft stBakc;
        address bayc;
        address mayc;
        address bakc;
        address botAdmin;
    }
    StakerStorage internal _stakerStorage;

    modifier onlyBot() {
        require(_msgSender() == _stakerStorage.botAdmin, "BendStakeManager: caller is not bot admin");
        _;
    }

    modifier onlyApe(address nft_) {
        require(
            nft_ == _stakerStorage.bayc || nft_ == _stakerStorage.mayc || nft_ == _stakerStorage.bakc,
            "BendStakeManager: nft must be ape"
        );
        _;
    }

    modifier onlyCoinPool() {
        require(_msgSender() == address(_stakerStorage.coinPool), "BendStakeManager: caller is not coin pool");
        _;
    }

    modifier onlyNftPool() {
        require(_msgSender() == address(_stakerStorage.nftPool), "BendStakeManager: caller is not nft pool");
        _;
    }

    modifier onlyWithdrawStrategyOrBot() {
        require(
            (_msgSender() == address(_stakerStorage.withdrawStrategy)) || (_msgSender() == _stakerStorage.botAdmin),
            "BendStakeManager: caller is not authorized"
        );
        _;
    }

    function initialize(
        IApeCoinStaking apeStaking_,
        ICoinPool coinPool_,
        INftPool nftPool_,
        INftVault nftVault_,
        IStakedNft stBayc_,
        IStakedNft stMayc_,
        IStakedNft stBakc_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        _stakerStorage.apeCoinStaking = apeStaking_;
        _stakerStorage.coinPool = coinPool_;
        _stakerStorage.nftPool = nftPool_;
        _stakerStorage.nftVault = nftVault_;
        _stakerStorage.apeCoin = IERC20Upgradeable(_stakerStorage.apeCoinStaking.apeCoin());

        _stakerStorage.apeCoin.approve(address(_stakerStorage.apeCoinStaking), type(uint256).max);
        _stakerStorage.apeCoin.approve(address(_stakerStorage.coinPool), type(uint256).max);
        _stakerStorage.apeCoin.approve(address(_stakerStorage.nftPool), type(uint256).max);
        _stakerStorage.apeCoin.approve(address(_stakerStorage.nftVault), type(uint256).max);

        _stakerStorage.stBayc = stBayc_;
        _stakerStorage.stMayc = stMayc_;
        _stakerStorage.stBakc = stBakc_;

        _stakerStorage.bayc = stBayc_.underlyingAsset();
        _stakerStorage.mayc = stMayc_.underlyingAsset();
        _stakerStorage.bakc = stBakc_.underlyingAsset();

        IERC721Upgradeable(_stakerStorage.bayc).setApprovalForAll(address(_stakerStorage.stBayc), true);
        IERC721Upgradeable(_stakerStorage.mayc).setApprovalForAll(address(_stakerStorage.stMayc), true);
        IERC721Upgradeable(_stakerStorage.bakc).setApprovalForAll(address(_stakerStorage.stBakc), true);
    }

    function stBayc() external view override returns (IStakedNft) {
        return _stakerStorage.stBayc;
    }

    function stMayc() external view override returns (IStakedNft) {
        return _stakerStorage.stMayc;
    }

    function stBakc() external view override returns (IStakedNft) {
        return _stakerStorage.stBakc;
    }

    function fee() external view override returns (uint256) {
        return _stakerStorage.fee;
    }

    function feeRecipient() external view override returns (address) {
        return _stakerStorage.feeRecipient;
    }

    function updateFee(uint256 fee_) external onlyOwner {
        require(fee_ <= MAX_FEE, "BendStakeManager: invalid fee");
        _stakerStorage.fee = fee_;
    }

    function updateFeeRecipient(address recipient_) external onlyOwner {
        require(recipient_ != address(0), "BendStakeManager: invalid fee recipient");
        _stakerStorage.feeRecipient = recipient_;
    }

    function botAdmin() external view returns (address) {
        return _stakerStorage.botAdmin;
    }

    function updateBotAdmin(address botAdmin_) external override onlyOwner {
        require(botAdmin_ != address(0), "BendStakeManager: invalid bot admin");
        _stakerStorage.botAdmin = botAdmin_;
    }

    function updateRewardsStrategy(
        address nft_,
        IRewardsStrategy rewardsStrategy_
    ) external override onlyOwner onlyApe(nft_) {
        require(address(rewardsStrategy_) != address(0), "BendStakeManager: invalid reward strategy");
        _stakerStorage.rewardsStrategies[nft_] = rewardsStrategy_;
    }

    function rewardsStrategies(address nft_) external view returns (IRewardsStrategy) {
        return _stakerStorage.rewardsStrategies[nft_];
    }

    function getNftRewardsShare(address nft_) external view returns (uint256 nftShare) {
        require(
            address(_stakerStorage.rewardsStrategies[nft_]) != address(0),
            "BendStakeManager: invalid reward strategy"
        );
        nftShare = _stakerStorage.rewardsStrategies[nft_].getNftRewardsShare();
    }

    function updateWithdrawStrategy(IWithdrawStrategy withdrawStrategy_) external override onlyOwner {
        require(address(withdrawStrategy_) != address(0), "BendStakeManager: invalid withdraw strategy");
        _stakerStorage.withdrawStrategy = withdrawStrategy_;
    }

    function _calculateFee(uint256 rewardsAmount_) internal view returns (uint256 feeAmount) {
        return rewardsAmount_.mulDiv(_stakerStorage.fee, PERCENTAGE_FACTOR, MathUpgradeable.Rounding.Down);
    }

    function calculateFee(uint256 rewardsAmount_) external view returns (uint256 feeAmount) {
        return _calculateFee(rewardsAmount_);
    }

    function _collectFee(uint256 rewardsAmount_) internal returns (uint256 feeAmount) {
        if (rewardsAmount_ > 0 && _stakerStorage.fee > 0) {
            feeAmount = _calculateFee(rewardsAmount_);
            _stakerStorage.pendingFeeAmount += feeAmount;
        }
    }

    function pendingFeeAmount() external view override returns (uint256) {
        return _stakerStorage.pendingFeeAmount;
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        require(
            (_stakerStorage.bayc == msg.sender ||
                _stakerStorage.mayc == msg.sender ||
                _stakerStorage.bakc == msg.sender),
            "BendStakeManager: not ape nft"
        );
        return this.onERC721Received.selector;
    }

    function mintStNft(IStakedNft stNft_, address to_, uint256[] calldata tokenIds_) external onlyNftPool {
        stNft_.mint(to_, tokenIds_);
    }

    function withdrawApeCoin(uint256 required) external override onlyCoinPool returns (uint256 withdrawn) {
        require(address(_stakerStorage.withdrawStrategy) != address(0), "BendStakeManager: invalid withdraw stratege");
        return _stakerStorage.withdrawStrategy.withdrawApeCoin(required);
    }

    function totalStakedApeCoin() external view override returns (uint256 amount) {
        amount += _stakedApeCoin(ApeStakingLib.APE_COIN_POOL_ID);
        amount += _stakedApeCoin(ApeStakingLib.BAYC_POOL_ID);
        amount += _stakedApeCoin(ApeStakingLib.MAYC_POOL_ID);
        amount += _stakedApeCoin(ApeStakingLib.BAKC_POOL_ID);
    }

    function totalPendingRewards() external view override returns (uint256 amount) {
        amount += _pendingRewards(ApeStakingLib.APE_COIN_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.BAYC_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.MAYC_POOL_ID);
        amount += _pendingRewards(ApeStakingLib.BAKC_POOL_ID);
        if (_stakerStorage.fee > 0) {
            amount -= _calculateFee(amount);
        }
    }

    function stakedApeCoin(uint256 poolId_) external view override returns (uint256) {
        return _stakedApeCoin(poolId_);
    }

    function _stakedApeCoin(uint256 poolId_) internal view returns (uint256) {
        if (poolId_ == ApeStakingLib.APE_COIN_POOL_ID) {
            return _stakerStorage.apeCoinPoolStakedAmount;
        }
        return
            _stakerStorage
                .nftVault
                .positionOf(_stakerStorage.apeCoinStaking.nftContracts(poolId_), address(this))
                .stakedAmount;
    }

    function _pendingRewards(uint256 poolId_) internal view returns (uint256) {
        if (poolId_ == ApeStakingLib.APE_COIN_POOL_ID) {
            return _stakerStorage.apeCoinStaking.pendingRewards(ApeStakingLib.APE_COIN_POOL_ID, address(this), 0);
        }
        return
            _stakerStorage.nftVault.pendingRewards(_stakerStorage.apeCoinStaking.nftContracts(poolId_), address(this));
    }

    function pendingRewards(uint256 poolId_) external view override returns (uint256 amount) {
        amount = _pendingRewards(poolId_);
        if (_stakerStorage.fee > 0) {
            amount -= _calculateFee(amount);
        }
    }

    function _prepareApeCoin(uint256 requiredAmount_) internal {
        uint256 pendingApeCoin = _stakerStorage.coinPool.pendingApeCoin();
        if (pendingApeCoin >= requiredAmount_) {
            _stakerStorage.coinPool.pullApeCoin(requiredAmount_);
        } else {
            if (_pendingRewards(ApeStakingLib.APE_COIN_POOL_ID) > 0) {
                _claimApeCoin();
                pendingApeCoin = _stakerStorage.coinPool.pendingApeCoin();
            }
            if (pendingApeCoin < requiredAmount_) {
                uint256 unstakeAmount = requiredAmount_ - pendingApeCoin;

                if (_stakedApeCoin(ApeStakingLib.APE_COIN_POOL_ID) >= unstakeAmount) {
                    _unstakeApeCoin(unstakeAmount);
                }
            }
            _stakerStorage.coinPool.pullApeCoin(requiredAmount_);
        }
    }

    function _stakeApeCoin(uint256 amount_) internal {
        _stakerStorage.coinPool.pullApeCoin(amount_);
        _stakerStorage.apeCoinStaking.depositSelfApeCoin(amount_);
        _stakerStorage.apeCoinPoolStakedAmount += amount_;
    }

    function stakeApeCoin(uint256 amount_) external override onlyBot {
        _stakeApeCoin(amount_);
    }

    function _unstakeApeCoin(uint256 amount_) internal {
        uint256 receivedApeCoin = _stakerStorage.apeCoin.balanceOf(address(this));
        _stakerStorage.apeCoinStaking.withdrawSelfApeCoin(amount_);
        receivedApeCoin = _stakerStorage.apeCoin.balanceOf(address(this)) - receivedApeCoin;
        _stakerStorage.apeCoinPoolStakedAmount -= amount_;

        if (receivedApeCoin > amount_) {
            receivedApeCoin -= _collectFee(receivedApeCoin - amount_);
        }
        uint256 rewardsAmount = receivedApeCoin - amount_;
        _stakerStorage.coinPool.receiveApeCoin(amount_, rewardsAmount);
    }

    function unstakeApeCoin(uint256 amount_) external override onlyWithdrawStrategyOrBot {
        _unstakeApeCoin(amount_);
    }

    function _claimApeCoin() internal {
        uint256 rewardsAmount = _stakerStorage.apeCoin.balanceOf(address(this));
        _stakerStorage.apeCoinStaking.claimSelfApeCoin();
        rewardsAmount = _stakerStorage.apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        _stakerStorage.coinPool.receiveApeCoin(0, rewardsAmount);
    }

    function claimApeCoin() external override onlyWithdrawStrategyOrBot {
        _claimApeCoin();
    }

    function _stakeBayc(uint256[] calldata tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 maxCap = _stakerStorage.apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAYC_POOL_ID).capPerPosition;
        uint256 tokenId_;
        uint256 apeCoinAmount = 0;
        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({tokenId: uint32(tokenId_), amount: uint224(maxCap)});
            apeCoinAmount += maxCap;
        }
        _prepareApeCoin(apeCoinAmount);
        _stakerStorage.nftVault.stakeBaycPool(nfts_);
    }

    function stakeBayc(uint256[] calldata tokenIds_) external override onlyBot {
        _stakeBayc(tokenIds_);
    }

    function _unstakeBayc(uint256[] calldata tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 tokenId_;
        address nft_ = _stakerStorage.bayc;

        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({
                tokenId: uint32(tokenId_),
                amount: uint224(_stakerStorage.apeCoinStaking.getNftPosition(nft_, tokenId_).stakedAmount)
            });
        }
        uint256 receivedAmount = _stakerStorage.apeCoin.balanceOf(address(this));
        (uint256 principalAmount, uint256 rewardsAmount) = _stakerStorage.nftVault.unstakeBaycPool(
            nfts_,
            address(this)
        );
        receivedAmount = _stakerStorage.apeCoin.balanceOf(address(this)) - receivedAmount;
        require(receivedAmount == (principalAmount + rewardsAmount), "BendStakeManager: unstake bayc error");

        _stakerStorage.coinPool.receiveApeCoin(principalAmount, 0);
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function unstakeBayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _unstakeBayc(tokenIds_);
    }

    function _claimBayc(uint256[] calldata tokenIds_) internal {
        uint256 rewardsAmount = _stakerStorage.apeCoin.balanceOf(address(this));
        address nft_ = _stakerStorage.bayc;
        _stakerStorage.nftVault.claimBaycPool(tokenIds_, address(this));
        rewardsAmount = _stakerStorage.apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function claimBayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _claimBayc(tokenIds_);
    }

    function _stakeMayc(uint256[] calldata tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 maxCap = _stakerStorage.apeCoinStaking.getCurrentTimeRange(ApeStakingLib.MAYC_POOL_ID).capPerPosition;
        uint256 tokenId_;
        uint256 apeCoinAmount = 0;
        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({tokenId: uint32(tokenId_), amount: uint224(maxCap)});
            apeCoinAmount += maxCap;
        }
        _prepareApeCoin(apeCoinAmount);
        _stakerStorage.nftVault.stakeMaycPool(nfts_);
    }

    function stakeMayc(uint256[] calldata tokenIds_) external override onlyBot {
        _stakeMayc(tokenIds_);
    }

    function _unstakeMayc(uint256[] calldata tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 tokenId_;
        address nft_ = _stakerStorage.mayc;

        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({
                tokenId: uint32(tokenId_),
                amount: uint224(_stakerStorage.apeCoinStaking.getNftPosition(nft_, tokenId_).stakedAmount)
            });
        }
        uint256 receivedAmount = _stakerStorage.apeCoin.balanceOf(address(this));
        (uint256 principalAmount, uint256 rewardsAmount) = _stakerStorage.nftVault.unstakeMaycPool(
            nfts_,
            address(this)
        );
        receivedAmount = _stakerStorage.apeCoin.balanceOf(address(this)) - receivedAmount;
        require(receivedAmount == (principalAmount + rewardsAmount), "BendStakeManager: unstake mayc error");

        // return principao to ape coin pool
        _stakerStorage.coinPool.receiveApeCoin(principalAmount, 0);
        rewardsAmount -= _collectFee(rewardsAmount);
        // distribute mayc rewardsAmount
        _distributeRewards(nft_, rewardsAmount);
    }

    function unstakeMayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _unstakeMayc(tokenIds_);
    }

    function _claimMayc(uint256[] calldata tokenIds_) internal {
        uint256 rewardsAmount = _stakerStorage.apeCoin.balanceOf(address(this));
        address nft_ = _stakerStorage.mayc;
        _stakerStorage.nftVault.claimMaycPool(tokenIds_, address(this));
        rewardsAmount = _stakerStorage.apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function claimMayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _claimMayc(tokenIds_);
    }

    function _stakeBakc(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_
    ) internal {
        IApeCoinStaking.PairNftDepositWithAmount[]
            memory baycPairsWithAmount_ = new IApeCoinStaking.PairNftDepositWithAmount[](baycPairs_.length);

        IApeCoinStaking.PairNftDepositWithAmount[]
            memory maycPairsWithAmount_ = new IApeCoinStaking.PairNftDepositWithAmount[](maycPairs_.length);

        uint256 maxCap = _stakerStorage.apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAKC_POOL_ID).capPerPosition;
        uint256 apeCoinAmount = 0;
        IApeCoinStaking.PairNft memory pair_;
        for (uint256 i = 0; i < baycPairsWithAmount_.length; i++) {
            pair_ = baycPairs_[i];
            baycPairsWithAmount_[i] = IApeCoinStaking.PairNftDepositWithAmount({
                mainTokenId: uint32(pair_.mainTokenId),
                bakcTokenId: uint32(pair_.bakcTokenId),
                amount: uint184(maxCap)
            });
            apeCoinAmount += maxCap;
        }
        for (uint256 i = 0; i < maycPairsWithAmount_.length; i++) {
            pair_ = maycPairs_[i];
            maycPairsWithAmount_[i] = IApeCoinStaking.PairNftDepositWithAmount({
                mainTokenId: uint32(pair_.mainTokenId),
                bakcTokenId: uint32(pair_.bakcTokenId),
                amount: uint184(maxCap)
            });
            apeCoinAmount += maxCap;
        }

        _prepareApeCoin(apeCoinAmount);

        _stakerStorage.nftVault.stakeBakcPool(baycPairsWithAmount_, maycPairsWithAmount_);
    }

    function stakeBakc(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_
    ) external override onlyBot {
        _stakeBakc(baycPairs_, maycPairs_);
    }

    function _unstakeBakc(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_
    ) internal {
        address nft_ = _stakerStorage.bakc;
        IApeCoinStaking.PairNftWithdrawWithAmount[]
            memory baycPairsWithAmount_ = new IApeCoinStaking.PairNftWithdrawWithAmount[](baycPairs_.length);

        IApeCoinStaking.PairNftWithdrawWithAmount[]
            memory maycPairsWithAmount_ = new IApeCoinStaking.PairNftWithdrawWithAmount[](maycPairs_.length);

        IApeCoinStaking.PairNft memory pair_;
        for (uint256 i = 0; i < baycPairsWithAmount_.length; i++) {
            pair_ = baycPairs_[i];
            baycPairsWithAmount_[i] = IApeCoinStaking.PairNftWithdrawWithAmount({
                mainTokenId: uint32(pair_.mainTokenId),
                bakcTokenId: uint32(pair_.bakcTokenId),
                amount: 0,
                isUncommit: true
            });
        }
        for (uint256 i = 0; i < maycPairsWithAmount_.length; i++) {
            pair_ = maycPairs_[i];
            maycPairsWithAmount_[i] = IApeCoinStaking.PairNftWithdrawWithAmount({
                mainTokenId: uint32(pair_.mainTokenId),
                bakcTokenId: uint32(pair_.bakcTokenId),
                amount: 0,
                isUncommit: true
            });
        }
        uint256 receivedAmount = _stakerStorage.apeCoin.balanceOf(address(this));
        (uint256 principalAmount, uint256 rewardsAmount) = _stakerStorage.nftVault.unstakeBakcPool(
            baycPairsWithAmount_,
            maycPairsWithAmount_,
            address(this)
        );
        receivedAmount = _stakerStorage.apeCoin.balanceOf(address(this)) - receivedAmount;
        require(receivedAmount == (principalAmount + rewardsAmount), "BendStakeManager: unstake bakc error");

        // return principao to ape coin pool
        _stakerStorage.coinPool.receiveApeCoin(principalAmount, 0);
        rewardsAmount -= _collectFee(rewardsAmount);
        // distribute bakc rewardsAmount
        _distributeRewards(nft_, rewardsAmount);
    }

    function unstakeBakc(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_
    ) external override onlyWithdrawStrategyOrBot {
        _unstakeBakc(baycPairs_, maycPairs_);
    }

    function _claimBakc(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_
    ) internal {
        uint256 rewardsAmount = _stakerStorage.apeCoin.balanceOf(address(this));
        address nft_ = _stakerStorage.bakc;
        _stakerStorage.nftVault.claimBakcPool(baycPairs_, maycPairs_, address(this));
        rewardsAmount = _stakerStorage.apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function claimBakc(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_
    ) external override onlyWithdrawStrategyOrBot {
        _claimBakc(baycPairs_, maycPairs_);
    }

    function _withdrawRefund(address nft_) internal {
        INftVault.Refund memory refund = _stakerStorage.nftVault.refundOf(nft_, address(this));
        _stakerStorage.nftVault.withdrawRefunds(nft_);
        if (refund.principal > 0) {
            _stakerStorage.coinPool.receiveApeCoin(refund.principal, 0);
        }
        if (refund.reward > 0) {
            uint256 rewardsAmount = refund.reward - _collectFee(refund.reward);
            _distributeRewards(nft_, rewardsAmount);
        }
    }

    function withdrawRefund(address nft_) external override onlyWithdrawStrategyOrBot {
        _withdrawRefund(nft_);
    }

    function _distributeRewards(address nft_, uint256 rewardsAmount_) internal {
        require(
            address(_stakerStorage.rewardsStrategies[nft_]) != address(0),
            "BendStakeManager: reward strategy can't be zero address"
        );
        uint256 nftShare = _stakerStorage.rewardsStrategies[nft_].getNftRewardsShare();
        require(nftShare < PERCENTAGE_FACTOR, "BaseRewardsStrategy: nft share is too high");
        uint256 nftPoolRewards = rewardsAmount_.mulDiv(nftShare, PERCENTAGE_FACTOR, MathUpgradeable.Rounding.Down);

        uint256 apeCoinPoolRewards = rewardsAmount_ - nftPoolRewards;
        _stakerStorage.coinPool.receiveApeCoin(0, apeCoinPoolRewards);
        _stakerStorage.nftPool.receiveApeCoin(nft_, nftPoolRewards);
    }

    function _withdrawTotalRefund() internal {
        _withdrawRefund(_stakerStorage.bayc);
        _withdrawRefund(_stakerStorage.mayc);
        _withdrawRefund(_stakerStorage.bakc);
    }

    function withdrawTotalRefund() external override onlyWithdrawStrategyOrBot {
        _withdrawTotalRefund();
    }

    function _refundOf(address nft_) internal view returns (uint256 principal, uint256 reward) {
        INftVault.Refund memory refund = _stakerStorage.nftVault.refundOf(nft_, address(this));
        principal = refund.principal;
        reward = refund.reward;
    }

    function refundOf(address nft_) external view onlyApe(nft_) returns (uint256 amount) {
        (uint256 principal, uint256 reward) = _refundOf(nft_);
        amount = principal + reward;
        if (_stakerStorage.fee > 0) {
            amount -= _calculateFee(reward);
        }
    }

    function _totalRefund() internal view returns (uint256 principal, uint256 reward) {
        INftVault.Refund memory refund_ = _stakerStorage.nftVault.refundOf(_stakerStorage.bayc, address(this));
        principal += refund_.principal;
        reward += refund_.reward;

        refund_ = _stakerStorage.nftVault.refundOf(_stakerStorage.mayc, address(this));
        principal += refund_.principal;
        reward += refund_.reward;

        refund_ = _stakerStorage.nftVault.refundOf(_stakerStorage.bakc, address(this));
        principal += refund_.principal;
        reward += refund_.reward;
    }

    function totalRefund() external view override returns (uint256 amount) {
        (uint256 principal, uint256 reward) = _totalRefund();
        amount = principal + reward;
        if (_stakerStorage.fee > 0) {
            amount -= _calculateFee(reward);
        }
    }

    function _compoudNftPool() internal {
        _stakerStorage.nftPool.compoundApeCoin(_stakerStorage.bayc);
        _stakerStorage.nftPool.compoundApeCoin(_stakerStorage.mayc);
        _stakerStorage.nftPool.compoundApeCoin(_stakerStorage.bakc);
    }

    function compoudNftPool() external onlyBot {
        _compoudNftPool();
    }

    function compound(CompoundArgs calldata args_) external override nonReentrant onlyBot {
        uint256 claimedNfts;

        // withdraw refunds which caused by users active burn the staked NFT
        address nft_ = _stakerStorage.bayc;
        (uint256 principal, uint256 reward) = _refundOf(nft_);
        if (principal > 0 || reward > 0) {
            _withdrawRefund(nft_);
        }
        nft_ = _stakerStorage.mayc;
        (principal, reward) = _refundOf(nft_);
        if (principal > 0 || reward > 0) {
            _withdrawRefund(nft_);
        }
        nft_ = _stakerStorage.bakc;
        (principal, reward) = _refundOf(nft_);
        if (principal > 0 || reward > 0) {
            _withdrawRefund(nft_);
        }

        // claim rewards from coin pool
        if (args_.claimCoinPool) {
            _claimApeCoin();
        }

        // claim rewards from NFT pool
        if (args_.claim.bayc.length > 0) {
            claimedNfts += args_.claim.bayc.length;
            _claimBayc(args_.claim.bayc);
        }
        if (args_.claim.mayc.length > 0) {
            claimedNfts += args_.claim.mayc.length;
            _claimMayc(args_.claim.mayc);
        }
        if (args_.claim.baycPairs.length > 0 || args_.claim.maycPairs.length > 0) {
            claimedNfts += args_.claim.baycPairs.length;
            claimedNfts += args_.claim.maycPairs.length;
            _claimBakc(args_.claim.baycPairs, args_.claim.maycPairs);
        }

        // unstake some NFTs from NFT pool
        if (args_.unstake.bayc.length > 0) {
            _unstakeBayc(args_.unstake.bayc);
        }
        if (args_.unstake.mayc.length > 0) {
            _unstakeMayc(args_.unstake.mayc);
        }
        if (args_.unstake.baycPairs.length > 0 || args_.unstake.maycPairs.length > 0) {
            _unstakeBakc(args_.unstake.baycPairs, args_.unstake.maycPairs);
        }

        // stake some NFTs to NFT pool
        if (args_.stake.bayc.length > 0) {
            _stakeBayc(args_.stake.bayc);
        }
        if (args_.stake.mayc.length > 0) {
            _stakeMayc(args_.stake.mayc);
        }
        if (args_.stake.baycPairs.length > 0 || args_.stake.maycPairs.length > 0) {
            _stakeBakc(args_.stake.baycPairs, args_.stake.maycPairs);
        }

        // compound ape coin in nft pool
        _compoudNftPool();

        // stake ape coin to coin pool
        if (_stakerStorage.coinPool.pendingApeCoin() >= args_.coinStakeThreshold) {
            _stakeApeCoin(_stakerStorage.coinPool.pendingApeCoin());
        }

        // transfer fee to recipient
        if (_stakerStorage.pendingFeeAmount > MAX_PENDING_FEE && _stakerStorage.feeRecipient != address(0)) {
            _stakerStorage.apeCoin.transfer(_stakerStorage.feeRecipient, _stakerStorage.pendingFeeAmount);
            // solhint-disable-next-line
            _stakerStorage.pendingFeeAmount = 0;
        }

        emit Compounded(args_.claimCoinPool, claimedNfts);
    }
}
