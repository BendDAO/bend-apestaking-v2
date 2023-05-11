// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IStakeManager, IApeCoinStaking} from "./interfaces/IStakeManager.sol";
import {INftVault} from "./interfaces/INftVault.sol";
import {ICoinPool} from "./interfaces/ICoinPool.sol";
import {INftPool} from "./interfaces/INftPool.sol";
import {IStakedNft} from "./interfaces/IStakedNft.sol";
import {IRewardsStrategy} from "./interfaces/IRewardsStrategy.sol";
import {IWithdrawStrategy} from "./interfaces/IWithdrawStrategy.sol";

import {ApeStakingLib} from "./libraries/ApeStakingLib.sol";

contract BendStakeManager is IStakeManager, OwnableUpgradeable {
    using ApeStakingLib for IApeCoinStaking;

    uint256 public constant PERCENTAGE_FACTOR = 1e4;
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant MAX_PENDING_FEE = 100 * 1e18;

    mapping(address => IRewardsStrategy) public rewardsStrategies;
    IWithdrawStrategy public withdrawStrategy;

    uint256 public override fee;
    address public override feeRecipient;
    uint256 public override pendingFeeAmount;
    uint256 public apeCoinPoolStakedAmount;

    IApeCoinStaking public apeCoinStaking;
    IERC20Upgradeable public apeCoin;

    INftVault public nftVault;
    ICoinPool public coinPool;
    INftPool public nftPool;

    IStakedNft public stBayc;
    IStakedNft public stMayc;
    IStakedNft public stBakc;

    address public bayc;
    address public mayc;
    address public bakc;

    address public botAdmin;

    modifier onlyBot() {
        require(_msgSender() == botAdmin, "BendStakeManager: caller is not bot admin");
        _;
    }

    modifier onlyApe(address nft_) {
        require(nft_ == bayc || nft_ == mayc || nft_ == bakc, "BendStakeManager: nft must be ape");
        _;
    }

    modifier onlyCoinPool() {
        require(_msgSender() == address(coinPool), "BendStakeManager: caller is not coin pool");
        _;
    }

    modifier onlyNftPool() {
        require(_msgSender() == address(nftPool), "BendStakeManager: caller is not nft pool");
        _;
    }

    modifier onlyWithdrawStrategyOrBot() {
        require(
            (_msgSender() == address(withdrawStrategy)) || (_msgSender() == botAdmin),
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
        apeCoinStaking = apeStaking_;
        coinPool = coinPool_;
        nftPool = nftPool_;
        nftVault = nftVault_;
        apeCoin = IERC20Upgradeable(apeCoinStaking.apeCoin());

        apeCoin.approve(address(apeCoinStaking), type(uint256).max);
        apeCoin.approve(address(coinPool), type(uint256).max);
        apeCoin.approve(address(nftPool), type(uint256).max);
        apeCoin.approve(address(nftVault), type(uint256).max);

        stBayc = stBayc_;
        stMayc = stMayc_;
        stBakc = stBakc_;

        bayc = stBayc_.underlyingAsset();
        mayc = stMayc_.underlyingAsset();
        bakc = stBakc_.underlyingAsset();

        IERC721Upgradeable(bayc).setApprovalForAll(address(stBayc), true);
        IERC721Upgradeable(mayc).setApprovalForAll(address(stMayc), true);
        IERC721Upgradeable(bakc).setApprovalForAll(address(stBakc), true);
    }

    function updateFee(uint256 fee_) external onlyOwner {
        require(fee_ >= 0 && fee_ <= MAX_FEE, "BendStakeManager: invalid fee");
        fee = fee_;
    }

    function updateFeeRecipient(address recipient_) external onlyOwner {
        require(recipient_ != address(0), "BendStakeManager: invalid fee recipient");
        feeRecipient = recipient_;
    }

    function updateBotAdmin(address botAdmin_) external override onlyOwner {
        botAdmin = botAdmin_;
    }

    function updateRewardsStrategy(
        address nft_,
        IRewardsStrategy rewardsStrategy_
    ) external override onlyOwner onlyApe(nft_) {
        rewardsStrategies[nft_] = rewardsStrategy_;
    }

    function updateWithdrawStrategy(IWithdrawStrategy withdrawStrategy_) external override onlyOwner {
        withdrawStrategy = withdrawStrategy_;
    }

    function _calculateFee(uint256 rewardsAmount_) internal view returns (uint256 feeAmount) {
        return (rewardsAmount_ * fee) / PERCENTAGE_FACTOR;
    }

    function calculateFee(uint256 rewardsAmount_) public view returns (uint256 feeAmount) {
        return _calculateFee(rewardsAmount_);
    }

    function _collectFee(uint256 rewardsAmount_) internal returns (uint256 feeAmount) {
        if (rewardsAmount_ > 0 && fee > 0) {
            feeAmount = _calculateFee(rewardsAmount_);
            pendingFeeAmount += feeAmount;
        }
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        require((bayc == msg.sender || mayc == msg.sender || bakc == msg.sender), "BendStakeManager: not ape nft");
        return this.onERC721Received.selector;
    }

    function mintStNft(IStakedNft stNft_, address to_, uint256[] calldata tokenIds_) external onlyNftPool {
        stNft_.mint(to_, tokenIds_);
    }

    function withdrawApeCoin(uint256 required) external override onlyCoinPool returns (uint256 withdrawn) {
        require(address(withdrawStrategy) != address(0), "BendStakeManager: invalid withdraw stratege");
        return withdrawStrategy.withdrawApeCoin(required);
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
        if (fee > 0) {
            amount -= _calculateFee(amount);
        }
    }

    function stakedApeCoin(uint256 poolId_) external view override returns (uint256) {
        return _stakedApeCoin(poolId_);
    }

    function _stakedApeCoin(uint256 poolId_) internal view returns (uint256) {
        if (poolId_ == ApeStakingLib.APE_COIN_POOL_ID) {
            return apeCoinPoolStakedAmount;
        }
        return nftVault.positionOf(apeCoinStaking.nftContracts(poolId_), address(this)).stakedAmount;
    }

    function _pendingRewards(uint256 poolId_) internal view returns (uint256) {
        if (poolId_ == ApeStakingLib.APE_COIN_POOL_ID) {
            return apeCoinStaking.pendingRewards(ApeStakingLib.APE_COIN_POOL_ID, address(this), 0);
        }
        return nftVault.pendingRewards(apeCoinStaking.nftContracts(poolId_), address(this));
    }

    function pendingRewards(uint256 poolId_) external view override returns (uint256 amount) {
        amount = _pendingRewards(poolId_);
        if (fee > 0) {
            amount -= _calculateFee(amount);
        }
    }

    function _prepareApeCoin(uint256 requiredAmount_) internal {
        uint256 pendingApeCoin = coinPool.pendingApeCoin();
        if (pendingApeCoin >= requiredAmount_) {
            coinPool.pullApeCoin(requiredAmount_);
        } else {
            if (_pendingRewards(ApeStakingLib.APE_COIN_POOL_ID) > 0) {
                _claimApeCoin();
                pendingApeCoin = coinPool.pendingApeCoin();
            }
            if (pendingApeCoin < requiredAmount_) {
                uint256 unstakeAmount = requiredAmount_ - pendingApeCoin;

                if (_stakedApeCoin(ApeStakingLib.APE_COIN_POOL_ID) >= unstakeAmount) {
                    _unstakeApeCoin(unstakeAmount);
                }
            }
            coinPool.pullApeCoin(requiredAmount_);
        }
    }

    function _stakeApeCoin(uint256 amount_) internal {
        coinPool.pullApeCoin(amount_);
        apeCoinStaking.depositSelfApeCoin(amount_);
        apeCoinPoolStakedAmount += amount_;
    }

    function stakeApeCoin(uint256 amount_) external override onlyBot {
        _stakeApeCoin(amount_);
    }

    function _unstakeApeCoin(uint256 amount_) internal {
        uint256 receivedApeCoin = apeCoin.balanceOf(address(this));
        apeCoinStaking.withdrawSelfApeCoin(amount_);
        receivedApeCoin = apeCoin.balanceOf(address(this)) - receivedApeCoin;
        apeCoinPoolStakedAmount -= amount_;

        if (receivedApeCoin > amount_) {
            receivedApeCoin -= _collectFee(receivedApeCoin - amount_);
        }
        uint256 rewardsAmount = receivedApeCoin - amount_;
        coinPool.receiveApeCoin(amount_, rewardsAmount);
    }

    function unstakeApeCoin(uint256 amount_) external override onlyWithdrawStrategyOrBot {
        _unstakeApeCoin(amount_);
    }

    function _claimApeCoin() internal {
        uint256 rewardsAmount = apeCoin.balanceOf(address(this));
        apeCoinStaking.claimSelfApeCoin();
        rewardsAmount = apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        coinPool.receiveApeCoin(0, rewardsAmount);
    }

    function claimApeCoin() external override onlyWithdrawStrategyOrBot {
        _claimApeCoin();
    }

    function _stakeBayc(uint256[] calldata tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 maxCap = apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAYC_POOL_ID).capPerPosition;
        uint256 tokenId_;
        uint256 apeCoinAmount = 0;
        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({tokenId: uint32(tokenId_), amount: uint224(maxCap)});
            apeCoinAmount += maxCap;
        }
        _prepareApeCoin(apeCoinAmount);
        nftVault.stakeBaycPool(nfts_);
    }

    function stakeBayc(uint256[] calldata tokenIds_) external override onlyBot {
        _stakeBayc(tokenIds_);
    }

    function _unstakeBayc(uint256[] calldata tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 tokenId_;
        address nft_ = bayc;

        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({
                tokenId: uint32(tokenId_),
                amount: uint224(apeCoinStaking.getNftPosition(nft_, tokenId_).stakedAmount)
            });
        }
        uint256 receivedAmount = apeCoin.balanceOf(address(this));
        (uint256 principalAmount, uint256 rewardsAmount) = nftVault.unstakeBaycPool(nfts_, address(this));
        receivedAmount = apeCoin.balanceOf(address(this)) - receivedAmount;
        require(receivedAmount == (principalAmount + rewardsAmount), "BendStakeManager: unstake bayc error");

        coinPool.receiveApeCoin(principalAmount, 0);
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function unstakeBayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _unstakeBayc(tokenIds_);
    }

    function _claimBayc(uint256[] calldata tokenIds_) internal {
        uint256 rewardsAmount = apeCoin.balanceOf(address(this));
        address nft_ = bayc;
        nftVault.claimBaycPool(tokenIds_, address(this));
        rewardsAmount = apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function claimBayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _claimBayc(tokenIds_);
    }

    function _stakeMayc(uint256[] calldata tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 maxCap = apeCoinStaking.getCurrentTimeRange(ApeStakingLib.MAYC_POOL_ID).capPerPosition;
        uint256 tokenId_;
        uint256 apeCoinAmount = 0;
        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({tokenId: uint32(tokenId_), amount: uint224(maxCap)});
            apeCoinAmount += maxCap;
        }
        _prepareApeCoin(apeCoinAmount);
        nftVault.stakeMaycPool(nfts_);
    }

    function stakeMayc(uint256[] calldata tokenIds_) external override onlyBot {
        _stakeMayc(tokenIds_);
    }

    function _unstakeMayc(uint256[] calldata tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 tokenId_;
        address nft_ = mayc;

        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({
                tokenId: uint32(tokenId_),
                amount: uint224(apeCoinStaking.getNftPosition(nft_, tokenId_).stakedAmount)
            });
        }
        uint256 receivedAmount = apeCoin.balanceOf(address(this));
        (uint256 principalAmount, uint256 rewardsAmount) = nftVault.unstakeMaycPool(nfts_, address(this));
        receivedAmount = apeCoin.balanceOf(address(this)) - receivedAmount;
        require(receivedAmount == (principalAmount + rewardsAmount), "BendStakeManager: unstake mayc error");

        // return principao to ape coin pool
        coinPool.receiveApeCoin(principalAmount, 0);
        rewardsAmount -= _collectFee(rewardsAmount);
        // distribute mayc rewardsAmount
        _distributeRewards(nft_, rewardsAmount);
    }

    function unstakeMayc(uint256[] calldata tokenIds_) external override onlyWithdrawStrategyOrBot {
        _unstakeMayc(tokenIds_);
    }

    function _claimMayc(uint256[] calldata tokenIds_) internal {
        uint256 rewardsAmount = apeCoin.balanceOf(address(this));
        address nft_ = mayc;
        nftVault.claimMaycPool(tokenIds_, address(this));
        rewardsAmount = apeCoin.balanceOf(address(this)) - rewardsAmount;
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

        uint256 maxCap = apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAKC_POOL_ID).capPerPosition;
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

        nftVault.stakeBakcPool(baycPairsWithAmount_, maycPairsWithAmount_);
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
        address nft_ = bakc;
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
        uint256 receivedAmount = apeCoin.balanceOf(address(this));
        (uint256 principalAmount, uint256 rewardsAmount) = nftVault.unstakeBakcPool(
            baycPairsWithAmount_,
            maycPairsWithAmount_,
            address(this)
        );
        receivedAmount = apeCoin.balanceOf(address(this)) - receivedAmount;
        require(receivedAmount == (principalAmount + rewardsAmount), "BendStakeManager: unstake bakc error");

        // return principao to ape coin pool
        coinPool.receiveApeCoin(principalAmount, 0);
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
        uint256 rewardsAmount = apeCoin.balanceOf(address(this));
        address nft_ = bakc;
        nftVault.claimBakcPool(baycPairs_, maycPairs_, address(this));
        rewardsAmount = apeCoin.balanceOf(address(this)) - rewardsAmount;
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
        INftVault.Refund memory refund = nftVault.refundOf(nft_, address(this));
        nftVault.withdrawRefunds(nft_);
        if (refund.principal > 0) {
            coinPool.receiveApeCoin(refund.principal, 0);
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
            address(rewardsStrategies[nft_]) != address(0),
            "BendStakeManager: reward strategy can't be zero address"
        );
        //TODO: static call
        uint256 nftPoolRewards = rewardsStrategies[nft_].calculateNftRewards(rewardsAmount_);

        uint256 apeCoinPoolRewards = rewardsAmount_ - nftPoolRewards;
        coinPool.receiveApeCoin(0, apeCoinPoolRewards);
        nftPool.receiveApeCoin(nft_, nftPoolRewards);
    }

    function _withdrawTotalRefund() internal {
        _withdrawRefund(bayc);
        _withdrawRefund(mayc);
        _withdrawRefund(bakc);
    }

    function withdrawTotalRefund() external override onlyWithdrawStrategyOrBot {
        _withdrawTotalRefund();
    }

    function _refundOf(address nft_) internal view returns (uint256 principal, uint256 reward) {
        INftVault.Refund memory refund = nftVault.refundOf(nft_, address(this));
        principal = refund.principal;
        reward = refund.reward;
    }

    function refundOf(address nft_) external view onlyApe(nft_) returns (uint256 amount) {
        (uint256 pricipal, uint256 reward) = _refundOf(nft_);
        amount = pricipal + reward;
        if (fee > 0) {
            amount -= _calculateFee(reward);
        }
    }

    function _totalRefund() internal view returns (uint256 principal, uint256 reward) {
        INftVault.Refund memory refund_ = nftVault.refundOf(bayc, address(this));
        principal += refund_.principal;
        reward += refund_.reward;

        refund_ = nftVault.refundOf(mayc, address(this));
        principal += refund_.principal;
        reward += refund_.reward;

        refund_ = nftVault.refundOf(bakc, address(this));
        principal += refund_.principal;
        reward += refund_.reward;
    }

    function totalRefund() external view override returns (uint256 amount) {
        (uint256 pricipal, uint256 reward) = _totalRefund();
        amount = pricipal + reward;
        if (fee > 0) {
            amount -= _calculateFee(reward);
        }
    }

    function compound(CompoundArgs calldata args_) external override onlyBot {
        // withdraw refunds which caused by users active burn the staked NFT
        address nft_ = bayc;
        (uint256 principal, uint256 reward) = _refundOf(nft_);
        if (principal > 0 || reward > 0) {
            _withdrawRefund(nft_);
        }
        nft_ = mayc;
        (principal, reward) = _refundOf(nft_);
        if (principal > 0 || reward > 0) {
            _withdrawRefund(nft_);
        }
        nft_ = bakc;
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
            _claimBayc(args_.claim.bayc);
        }
        if (args_.claim.mayc.length > 0) {
            _claimMayc(args_.claim.mayc);
        }
        if (args_.claim.baycPairs.length > 0 || args_.claim.maycPairs.length > 0) {
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

        // stake ape coin to coin pool
        if (coinPool.pendingApeCoin() >= args_.coinStakeThreshold) {
            _stakeApeCoin(coinPool.pendingApeCoin());
        }

        // transfer fee to recipient
        if (pendingFeeAmount > MAX_PENDING_FEE && feeRecipient != address(0)) {
            pendingFeeAmount = 0;
            apeCoin.transfer(feeRecipient, pendingFeeAmount);
        }
    }
}
