// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IApeCoinStaking} from "../interfaces/IApeCoinStaking.sol";
import {INftVault} from "../interfaces/INftVault.sol";
import {IWAPE} from "../interfaces/IWAPE.sol";

import {ApeStakingLib} from "../libraries/ApeStakingLib.sol";

library VaultLogic {
    event SingleNftUnstaked(address indexed nft, address indexed staker, uint256[] tokenIds, uint256[] amounts);

    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for uint248;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using ApeStakingLib for IApeCoinStaking;

    function _stakerOf(
        INftVault.VaultStorage storage _vaultStorage,
        address nft_,
        uint256 tokenId_
    ) internal view returns (address) {
        return _vaultStorage.nfts[nft_][tokenId_].staker;
    }

    function _ownerOf(
        INftVault.VaultStorage storage _vaultStorage,
        address nft_,
        uint256 tokenId_
    ) internal view returns (address) {
        return _vaultStorage.nfts[nft_][tokenId_].owner;
    }

    function _increasePosition(
        INftVault.VaultStorage storage _vaultStorage,
        address nft_,
        address staker_,
        uint256 stakedAmount_
    ) internal {
        INftVault.Position storage position_ = _vaultStorage.positions[nft_][staker_];
        position_.stakedAmount += stakedAmount_;
        position_.rewardsDebt += int256(
            stakedAmount_ * _vaultStorage.apeCoinStaking.getNftPool(nft_).accumulatedRewardsPerShare
        );
    }

    function _decreasePosition(
        INftVault.VaultStorage storage _vaultStorage,
        address nft_,
        address staker_,
        uint256 stakedAmount_
    ) internal {
        INftVault.Position storage position_ = _vaultStorage.positions[nft_][staker_];
        position_.stakedAmount -= stakedAmount_;
        position_.rewardsDebt -= int256(
            stakedAmount_ * _vaultStorage.apeCoinStaking.getNftPool(nft_).accumulatedRewardsPerShare
        );
    }

    function _updateRewardsDebt(
        INftVault.VaultStorage storage _vaultStorage,
        address nft_,
        address staker_,
        uint256 claimedRewardsAmount_
    ) internal {
        INftVault.Position storage position_ = _vaultStorage.positions[nft_][staker_];
        position_.rewardsDebt += int256(claimedRewardsAmount_ * ApeStakingLib.APE_COIN_PRECISION);
    }

    struct RefundSinglePoolVars {
        uint256 poolId;
        uint256 cachedBalance;
        uint256 tokenId;
        uint256 stakedAmount;
        // refunds
        address staker;
        uint256 totalPrincipal;
        uint256 totalReward;
        // array
        uint256 singleNftIndex;
        uint256 singleNftSize;
        uint256[] singleNftTokenIds;
        uint256[] singleNftAmounts;
    }

    function _refundSinglePool(
        INftVault.VaultStorage storage _vaultStorage,
        address nft_,
        uint256[] calldata tokenIds_
    ) external {
        require(tokenIds_.length > 0, "nftVault: invalid tokenIds");

        RefundSinglePoolVars memory vars;
        INftVault.Refund storage refund;

        if (nft_ == _vaultStorage.bayc) {
            vars.poolId = ApeStakingLib.BAYC_POOL_ID;
        } else if (nft_ == _vaultStorage.mayc) {
            vars.poolId = ApeStakingLib.MAYC_POOL_ID;
        } else if (nft_ == _vaultStorage.bakc) {
            vars.poolId = ApeStakingLib.BAKC_POOL_ID;
        } else {
            revert("nftVault: invalid nft");
        }
        vars.cachedBalance = _vaultStorage.wrapApeCoin.balanceOf(address(this));
        vars.staker = _stakerOf(_vaultStorage, nft_, tokenIds_[0]);
        require(vars.staker != address(0), "nftVault: invalid staker");

        // Calculate the nft array size
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            vars.tokenId = tokenIds_[i];
            require(msg.sender == _ownerOf(_vaultStorage, nft_, vars.tokenId), "nftVault: caller must be nft owner");
            // make sure the bayc/mayc locked in valult
            require(address(this) == IERC721Upgradeable(nft_).ownerOf(vars.tokenId), "nftVault: invalid token id");
            require(vars.staker == _stakerOf(_vaultStorage, nft_, vars.tokenId), "nftVault: staker must be same");
            vars.stakedAmount = _vaultStorage.apeCoinStaking.nftPosition(vars.poolId, vars.tokenId).stakedAmount;

            // Still have ape coin staking in single pool
            if (vars.stakedAmount > 0) {
                vars.singleNftSize += 1;
            }
        }

        if (vars.singleNftSize > 0) {
            vars.singleNftTokenIds = new uint256[](vars.singleNftSize);
            vars.singleNftAmounts = new uint256[](vars.singleNftSize);
            for (uint256 i = 0; i < tokenIds_.length; i++) {
                vars.tokenId = tokenIds_[i];
                vars.stakedAmount = _vaultStorage.apeCoinStaking.nftPosition(vars.poolId, vars.tokenId).stakedAmount;
                if (vars.stakedAmount > 0) {
                    vars.totalPrincipal += vars.stakedAmount;

                    vars.singleNftTokenIds[vars.singleNftIndex] = vars.tokenId;
                    vars.singleNftAmounts[vars.singleNftIndex] = vars.stakedAmount;
                    vars.singleNftIndex += 1;

                    _vaultStorage.stakingTokenIds[nft_][vars.staker].remove(vars.tokenId);
                }
            }

            // withdraw nft from staking, and wrap ape coin
            _vaultStorage.apeCoinStaking.withdraw(
                vars.poolId,
                vars.singleNftTokenIds,
                vars.singleNftAmounts,
                address(this)
            );
            IWAPE(address(_vaultStorage.wrapApeCoin)).deposit{value: address(this).balance}();

            vars.totalReward =
                _vaultStorage.wrapApeCoin.balanceOf(address(this)) -
                vars.cachedBalance -
                vars.totalPrincipal;

            // refund ape coin for single nft
            refund = _vaultStorage.refunds[nft_][vars.staker];
            refund.principal += vars.totalPrincipal;
            refund.reward += vars.totalReward;

            // update bayc&mayc position and debt
            if (vars.totalReward > 0) {
                _updateRewardsDebt(_vaultStorage, nft_, vars.staker, vars.totalReward);
            }
            _decreasePosition(_vaultStorage, nft_, vars.staker, vars.totalPrincipal);
            emit SingleNftUnstaked(nft_, vars.staker, vars.singleNftTokenIds, vars.singleNftAmounts);
        }
    }
}
