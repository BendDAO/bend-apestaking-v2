// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import {IStakeManager, IApeCoinStaking} from "./interfaces/IStakeManager.sol";
import {INftVault} from "./interfaces/INftVault.sol";
import {ICoinPool} from "./interfaces/ICoinPool.sol";
import {INftPool} from "./interfaces/INftPool.sol";
import {IStakedNft} from "./interfaces/IStakedNft.sol";
import {IRewardsStrategy} from "./interfaces/IRewardsStrategy.sol";

import {ApeStakingLib} from "./libraries/ApeStakingLib.sol";

contract BendStakeManager is IStakeManager, OwnableUpgradeable {
    using MathUpgradeable for uint256;
    using ApeStakingLib for IApeCoinStaking;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    uint256 public constant PERCENTAGE_FACTOR = 1e4;
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant MAX_PENDING_FEE = 100 * 1e18;

    mapping(address => IRewardsStrategy) public rewardsStrategies;
    mapping(uint256 => EnumerableSetUpgradeable.UintSet) private _stakedTokenIds;

    uint256 public override fee;
    address public override feeRecipient;
    uint256 public override pendingFeeAmount;
    uint256 public apeCoinPoolStakedAmount;

    IApeCoinStaking public apeCoinStaking;
    IERC20Upgradeable public apeCoin;
    address public bayc;
    address public mayc;
    address public bakc;

    INftVault public nftVault;
    ICoinPool public coinPool;
    INftPool public nftPool;

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

    function initialize(
        IApeCoinStaking apeStaking_,
        ICoinPool coinPool_,
        INftPool nftPool_,
        INftVault nftVault_
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

        bayc = address(apeCoinStaking.bayc());
        mayc = address(apeCoinStaking.mayc());
        bakc = address(apeCoinStaking.bakc());
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

    function _calculateFee(uint256 rewardsAmount_) internal view returns (uint256 feeAmount) {
        return rewardsAmount_.mulDiv(fee, PERCENTAGE_FACTOR, MathUpgradeable.Rounding.Down);
    }

    function _collectFee(uint256 rewardsAmount_) internal returns (uint256 feeAmount) {
        if (rewardsAmount_ > 0 && fee > 0) {
            feeAmount = _calculateFee(rewardsAmount_);
            pendingFeeAmount += feeAmount;
        }
    }

    function _coinPoolChangedAmount(uint256 initBalance_) internal view returns (uint256) {
        return apeCoin.balanceOf(address(coinPool)) - initBalance_;
    }

    struct WithdrawApeCoinVars {
        uint256 margin;
        uint256 tokenId;
        uint256 size;
        uint256 totalWithdrawn;
    }

    function withdrawApeCoin(uint256 required) external override onlyCoinPool returns (uint256 withdrawn) {
        uint256 initBalance = apeCoin.balanceOf(address(coinPool));
        // withdraw refund
        (uint256 principal, uint256 reward) = _totalRefund();
        if (principal > 0 || reward > 0) {
            _withdrawTotalRefund();
        }

        // claim ape coin pool
        if (_coinPoolChangedAmount(initBalance) < required && _pendingRewards(ApeStakingLib.APE_COIN_POOL_ID) > 0) {
            _claimApeCoin();
        }

        // unstake ape coin pool
        if (_coinPoolChangedAmount(initBalance) < required && _stakedApeCoin(ApeStakingLib.APE_COIN_POOL_ID) > 0) {
            _unstakeApeCoin(required - _coinPoolChangedAmount(initBalance));
        }
        WithdrawApeCoinVars memory vars;
        // unstake bayc
        if (_coinPoolChangedAmount(initBalance) < required && _stakedApeCoin(ApeStakingLib.BAYC_POOL_ID) > 0) {
            vars.margin = required - _coinPoolChangedAmount(initBalance);
            vars.tokenId = 0;
            vars.size = 0;
            vars.totalWithdrawn = 0;

            for (uint256 i = 0; i < _stakedTokenIds[ApeStakingLib.BAYC_POOL_ID].length(); i++) {
                vars.tokenId = _stakedTokenIds[ApeStakingLib.BAYC_POOL_ID].at(i);
                vars.totalWithdrawn += apeCoinStaking
                    .nftPosition(ApeStakingLib.BAYC_POOL_ID, vars.tokenId)
                    .stakedAmount;
                vars.totalWithdrawn += apeCoinStaking.pendingRewards(
                    ApeStakingLib.BAYC_POOL_ID,
                    address(this),
                    vars.tokenId
                );
                vars.size += 1;
                if (vars.totalWithdrawn >= vars.margin) {
                    break;
                }
            }
            if (vars.size > 0) {
                uint256[] memory tokenIds = new uint256[](vars.size);
                for (uint256 i = 0; i < vars.size; i++) {
                    tokenIds[i] = _stakedTokenIds[ApeStakingLib.BAYC_POOL_ID].at(i);
                }
                _unstakeBayc(tokenIds);
            }
        }

        // unstake mayc
        if (_coinPoolChangedAmount(initBalance) < required && _stakedApeCoin(ApeStakingLib.MAYC_POOL_ID) > 0) {
            vars.margin = required - _coinPoolChangedAmount(initBalance);
            vars.tokenId = 0;
            vars.size = 0;
            vars.totalWithdrawn = 0;
            for (uint256 i = 0; i < _stakedTokenIds[ApeStakingLib.MAYC_POOL_ID].length(); i++) {
                vars.tokenId = _stakedTokenIds[ApeStakingLib.MAYC_POOL_ID].at(i);
                vars.totalWithdrawn += apeCoinStaking
                    .nftPosition(ApeStakingLib.MAYC_POOL_ID, vars.tokenId)
                    .stakedAmount;
                vars.totalWithdrawn += apeCoinStaking.pendingRewards(
                    ApeStakingLib.MAYC_POOL_ID,
                    address(this),
                    vars.tokenId
                );
                vars.size += 1;
                if (vars.totalWithdrawn >= vars.margin) {
                    break;
                }
            }
            if (vars.size > 0) {
                uint256[] memory tokenIds = new uint256[](vars.size);
                for (uint256 i = 0; i < vars.size; i++) {
                    tokenIds[i] = _stakedTokenIds[ApeStakingLib.MAYC_POOL_ID].at(i);
                }
                _unstakeMayc(tokenIds);
            }
        }

        // unstake bakc
        if (_coinPoolChangedAmount(initBalance) < required && _stakedApeCoin(ApeStakingLib.BAKC_POOL_ID) > 0) {
            vars.margin = required - _coinPoolChangedAmount(initBalance);
            vars.tokenId = 0;
            vars.size = 0;
            vars.totalWithdrawn = 0;
            for (uint256 i = 0; i < _stakedTokenIds[ApeStakingLib.BAKC_POOL_ID].length(); i++) {
                vars.tokenId = _stakedTokenIds[ApeStakingLib.BAKC_POOL_ID].at(i);
                vars.totalWithdrawn += apeCoinStaking
                    .nftPosition(ApeStakingLib.BAKC_POOL_ID, vars.tokenId)
                    .stakedAmount;
                vars.totalWithdrawn += apeCoinStaking.pendingRewards(
                    ApeStakingLib.BAKC_POOL_ID,
                    address(this),
                    vars.tokenId
                );
                vars.size += 1;
                if (vars.totalWithdrawn >= vars.margin) {
                    break;
                }
            }
            if (vars.size > 0) {
                uint256 baycPairSize;
                uint256 baycPairIndex;
                uint256 maycPairSize;
                uint256 maycPairIndex;
                uint256 bakcTokenId;

                IApeCoinStaking.PairingStatus memory pairingStatus;
                for (uint256 i = 0; i < vars.size; i++) {
                    bakcTokenId = _stakedTokenIds[ApeStakingLib.BAKC_POOL_ID].at(i);
                    pairingStatus = apeCoinStaking.bakcToMain(bakcTokenId, ApeStakingLib.BAYC_POOL_ID);
                    if (pairingStatus.isPaired) {
                        baycPairSize += 1;
                    } else {
                        maycPairSize += 1;
                    }
                }
                IApeCoinStaking.PairNft[] memory baycPairs = new IApeCoinStaking.PairNft[](baycPairSize);
                IApeCoinStaking.PairNft[] memory maycPairs = new IApeCoinStaking.PairNft[](maycPairSize);
                for (uint256 i = 0; i < vars.size; i++) {
                    bakcTokenId = _stakedTokenIds[ApeStakingLib.BAKC_POOL_ID].at(i);
                    pairingStatus = apeCoinStaking.bakcToMain(bakcTokenId, ApeStakingLib.BAYC_POOL_ID);
                    if (pairingStatus.isPaired) {
                        baycPairs[baycPairIndex] = IApeCoinStaking.PairNft({
                            mainTokenId: _toUint128(pairingStatus.tokenId),
                            bakcTokenId: _toUint128(bakcTokenId)
                        });
                        baycPairIndex += 1;
                    } else {
                        pairingStatus = apeCoinStaking.bakcToMain(bakcTokenId, ApeStakingLib.MAYC_POOL_ID);
                        maycPairs[maycPairIndex] = IApeCoinStaking.PairNft({
                            mainTokenId: _toUint128(pairingStatus.tokenId),
                            bakcTokenId: _toUint128(bakcTokenId)
                        });
                        maycPairIndex += 1;
                    }
                }
                _unstakeBakc(baycPairs, maycPairs);
            }
        }

        withdrawn = _coinPoolChangedAmount(initBalance);
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

    function _claimApeCoin() internal {
        uint256 rewardsAmount = apeCoin.balanceOf(address(this));
        apeCoinStaking.claimSelfApeCoin();
        rewardsAmount = apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        coinPool.receiveApeCoin(0, rewardsAmount);
    }

    function _stakeBayc(uint256[] memory tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 maxCap = apeCoinStaking.getCurrentTimeRange(ApeStakingLib.BAYC_POOL_ID).capPerPosition;
        uint256 tokenId_;
        uint256 apeCoinAmount = 0;
        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({tokenId: _toUint32(tokenId_), amount: _toUint224(maxCap)});
            apeCoinAmount += maxCap;
            _stakedTokenIds[ApeStakingLib.BAYC_POOL_ID].add(tokenId_);
        }
        _prepareApeCoin(apeCoinAmount);
        nftVault.stakeBaycPool(nfts_);
    }

    function _unstakeBayc(uint256[] memory tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 tokenId_;
        address nft_ = bayc;

        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({
                tokenId: _toUint32(tokenId_),
                amount: _toUint224(apeCoinStaking.getNftPosition(nft_, tokenId_).stakedAmount)
            });
            _stakedTokenIds[ApeStakingLib.BAYC_POOL_ID].remove(tokenId_);
        }
        uint256 receivedAmount = apeCoin.balanceOf(address(this));
        (uint256 principalAmount, uint256 rewardsAmount) = nftVault.unstakeBaycPool(nfts_, address(this));
        receivedAmount = apeCoin.balanceOf(address(this)) - receivedAmount;
        require(receivedAmount == (principalAmount + rewardsAmount), "BendStakeManager: unstake bayc error");

        coinPool.receiveApeCoin(principalAmount, 0);
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function _claimBayc(uint256[] memory tokenIds_) internal {
        uint256 rewardsAmount = apeCoin.balanceOf(address(this));
        address nft_ = bayc;
        nftVault.claimBaycPool(tokenIds_, address(this));
        rewardsAmount = apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function _stakeMayc(uint256[] memory tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 maxCap = apeCoinStaking.getCurrentTimeRange(ApeStakingLib.MAYC_POOL_ID).capPerPosition;
        uint256 tokenId_;
        uint256 apeCoinAmount = 0;
        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({tokenId: _toUint32(tokenId_), amount: _toUint224(maxCap)});
            apeCoinAmount += maxCap;
            _stakedTokenIds[ApeStakingLib.MAYC_POOL_ID].add(tokenId_);
        }
        _prepareApeCoin(apeCoinAmount);
        nftVault.stakeMaycPool(nfts_);
    }

    function _unstakeMayc(uint256[] memory tokenIds_) internal {
        IApeCoinStaking.SingleNft[] memory nfts_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);
        uint256 tokenId_;
        address nft_ = mayc;

        for (uint256 i = 0; i < nfts_.length; i++) {
            tokenId_ = tokenIds_[i];
            nfts_[i] = IApeCoinStaking.SingleNft({
                tokenId: _toUint32(tokenId_),
                amount: _toUint224(apeCoinStaking.getNftPosition(nft_, tokenId_).stakedAmount)
            });
            _stakedTokenIds[ApeStakingLib.MAYC_POOL_ID].remove(tokenId_);
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

    function _claimMayc(uint256[] memory tokenIds_) internal {
        uint256 rewardsAmount = apeCoin.balanceOf(address(this));
        address nft_ = mayc;
        nftVault.claimMaycPool(tokenIds_, address(this));
        rewardsAmount = apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
    }

    function _stakeBakc(
        IApeCoinStaking.PairNft[] memory baycPairs_,
        IApeCoinStaking.PairNft[] memory maycPairs_
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
                mainTokenId: _toUint32(pair_.mainTokenId),
                bakcTokenId: _toUint32(pair_.bakcTokenId),
                amount: _toUint184(maxCap)
            });
            apeCoinAmount += maxCap;
            _stakedTokenIds[ApeStakingLib.BAKC_POOL_ID].add(pair_.bakcTokenId);
        }
        for (uint256 i = 0; i < maycPairsWithAmount_.length; i++) {
            pair_ = maycPairs_[i];
            maycPairsWithAmount_[i] = IApeCoinStaking.PairNftDepositWithAmount({
                mainTokenId: _toUint32(pair_.mainTokenId),
                bakcTokenId: _toUint32(pair_.bakcTokenId),
                amount: _toUint184(maxCap)
            });
            apeCoinAmount += maxCap;
            _stakedTokenIds[ApeStakingLib.BAKC_POOL_ID].add(pair_.bakcTokenId);
        }

        _prepareApeCoin(apeCoinAmount);

        nftVault.stakeBakcPool(baycPairsWithAmount_, maycPairsWithAmount_);
    }

    function _unstakeBakc(
        IApeCoinStaking.PairNft[] memory baycPairs_,
        IApeCoinStaking.PairNft[] memory maycPairs_
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
                mainTokenId: _toUint32(pair_.mainTokenId),
                bakcTokenId: _toUint32(pair_.bakcTokenId),
                amount: 0,
                isUncommit: true
            });
            _stakedTokenIds[ApeStakingLib.BAKC_POOL_ID].remove(pair_.bakcTokenId);
        }
        for (uint256 i = 0; i < maycPairsWithAmount_.length; i++) {
            pair_ = maycPairs_[i];
            maycPairsWithAmount_[i] = IApeCoinStaking.PairNftWithdrawWithAmount({
                mainTokenId: _toUint32(pair_.mainTokenId),
                bakcTokenId: _toUint32(pair_.bakcTokenId),
                amount: 0,
                isUncommit: true
            });
            _stakedTokenIds[ApeStakingLib.BAKC_POOL_ID].remove(pair_.bakcTokenId);
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

    function _claimBakc(
        IApeCoinStaking.PairNft[] memory baycPairs_,
        IApeCoinStaking.PairNft[] memory maycPairs_
    ) internal {
        uint256 rewardsAmount = apeCoin.balanceOf(address(this));
        address nft_ = bakc;
        nftVault.claimBakcPool(baycPairs_, maycPairs_, address(this));
        rewardsAmount = apeCoin.balanceOf(address(this)) - rewardsAmount;
        rewardsAmount -= _collectFee(rewardsAmount);
        _distributeRewards(nft_, rewardsAmount);
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
        (uint256 principal, ) = _refundOf(address(nft_));
        if (principal > 0) {
            _withdrawRefund(nft_);
        }
        nft_ = mayc;
        (principal, ) = _refundOf(address(nft_));
        if (principal > 0) {
            _withdrawRefund(nft_);
        }
        nft_ = bakc;
        (principal, ) = _refundOf(address(nft_));
        if (principal > 0) {
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

    function _toUint224(uint256 value) internal pure returns (uint224) {
        require(value <= type(uint224).max, "SafeCast: value doesn't fit in 224 bits");
        return uint224(value);
    }

    function _toUint184(uint256 value) internal pure returns (uint184) {
        require(value <= type(uint184).max, "SafeCast: value doesn't fit in 184 bits");
        return uint184(value);
    }

    function _toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    function _toUint32(uint256 value) internal pure returns (uint32) {
        require(value <= type(uint32).max, "SafeCast: value doesn't fit in 32 bits");
        return uint32(value);
    }
}
