// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IApeCoinStaking} from "../interfaces/IApeCoinStaking.sol";
import {INftVault} from "../interfaces/INftVault.sol";
import {ICoinPool} from "../interfaces/ICoinPool.sol";
import {INftPool} from "../interfaces/INftPool.sol";
import {IStakeManager} from "../interfaces/IStakeManager.sol";
import {IWithdrawStrategy} from "../interfaces/IWithdrawStrategy.sol";

import {ApeStakingLib} from "../libraries/ApeStakingLib.sol";

contract DefaultWithdrawStrategy is IWithdrawStrategy, ReentrancyGuardUpgradeable {
    using ApeStakingLib for IApeCoinStaking;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for uint248;

    IApeCoinStaking public apeCoinStaking;
    IERC20 public wrapApeCoin;
    IStakeManager public staker;
    ICoinPool public coinPool;
    INftVault public nftVault;

    address public bayc;
    address public mayc;
    address public bakc;

    modifier onlyStaker() {
        require(msg.sender == address(staker), "DWS: caller is not staker");
        _;
    }

    constructor(IApeCoinStaking apeCoinStaking_, INftVault nftVault_, ICoinPool coinPool_, IStakeManager staker_) {
        apeCoinStaking = apeCoinStaking_;
        nftVault = nftVault_;
        coinPool = coinPool_;
        staker = staker_;

        wrapApeCoin = IERC20(coinPool.getWrapApeCoin());
        bayc = address(apeCoinStaking.bayc());
        mayc = address(apeCoinStaking.mayc());
        bakc = address(apeCoinStaking.bakc());
    }

    function initGlobalState() public onlyStaker {
        wrapApeCoin = IERC20(coinPool.getWrapApeCoin());
    }

    struct WithdrawApeCoinVars {
        uint256 margin;
        uint256 tokenId;
        uint256 stakedApeCoin;
        uint256 pendingRewards;
        uint256 unstakeNftSize;
        uint256 totalWithdrawn;
        uint256 changedBalance;
        uint256 initBalance;
    }

    function withdrawApeCoin(uint256 required) external override onlyStaker returns (uint256 withdrawn) {
        require(address(wrapApeCoin) != address(0), "DWS: wrapApeCoin not set");

        WithdrawApeCoinVars memory vars;
        vars.initBalance = wrapApeCoin.balanceOf(address(coinPool));

        // 1. withdraw refund
        (uint256 refundPrincipal, uint256 refundReward) = staker.totalRefund();
        if (refundPrincipal > 0 || refundReward > 0) {
            staker.withdrawTotalRefund();
        }
        vars.changedBalance = _changedBalance(address(coinPool), vars.initBalance);

        // 2. claim ape coin pool
        if (vars.changedBalance < required) {
            vars.pendingRewards = staker.pendingRewards(ApeStakingLib.APE_COIN_POOL_ID);
            if (vars.pendingRewards > 0) {
                staker.claimApeCoin();
                vars.changedBalance = _changedBalance(address(coinPool), vars.initBalance);
            }
        }

        // 3. unstake ape coin pool
        if (vars.changedBalance < required) {
            vars.stakedApeCoin = staker.stakedApeCoin(ApeStakingLib.APE_COIN_POOL_ID);
            if (vars.stakedApeCoin > 0) {
                uint256 unstakeAmount = required - vars.changedBalance;
                if (unstakeAmount > vars.stakedApeCoin) {
                    unstakeAmount = vars.stakedApeCoin;
                }
                staker.unstakeApeCoin(unstakeAmount);
                vars.changedBalance = _changedBalance(address(coinPool), vars.initBalance);
            }
        }

        // 4. unstake bayc
        if (vars.changedBalance < required) {
            vars.stakedApeCoin = staker.stakedApeCoin(ApeStakingLib.BAYC_POOL_ID);
            if (vars.stakedApeCoin > 0) {
                vars.margin = required - vars.changedBalance;
                vars.tokenId = 0;
                vars.unstakeNftSize = 0;
                vars.totalWithdrawn = 0;
                vars.stakedApeCoin = 0;
                vars.pendingRewards = 0;
                for (uint256 i = 0; i < nftVault.totalStakingNft(bayc, address(staker)); i++) {
                    vars.tokenId = nftVault.stakingNftIdByIndex(bayc, address(staker), i);
                    vars.stakedApeCoin = apeCoinStaking
                        .nftPosition(ApeStakingLib.BAYC_POOL_ID, vars.tokenId)
                        .stakedAmount;

                    vars.pendingRewards = apeCoinStaking.pendingRewards(ApeStakingLib.BAYC_POOL_ID, vars.tokenId);
                    vars.pendingRewards -= staker.calculateFee(vars.pendingRewards);

                    vars.totalWithdrawn += vars.stakedApeCoin;
                    vars.totalWithdrawn += vars.pendingRewards;
                    vars.unstakeNftSize += 1;

                    if (vars.totalWithdrawn >= vars.margin) {
                        break;
                    }
                }
                if (vars.unstakeNftSize > 0) {
                    uint256[] memory tokenIds = new uint256[](vars.unstakeNftSize);
                    for (uint256 i = 0; i < vars.unstakeNftSize; i++) {
                        tokenIds[i] = nftVault.stakingNftIdByIndex(bayc, address(staker), i);
                    }
                    staker.unstakeBayc(tokenIds);
                    vars.changedBalance = _changedBalance(address(coinPool), vars.initBalance);
                }
            }
        }

        // 5. unstake mayc
        if (vars.changedBalance < required) {
            vars.stakedApeCoin = staker.stakedApeCoin(ApeStakingLib.MAYC_POOL_ID);
            if (vars.stakedApeCoin > 0) {
                vars.margin = required - vars.changedBalance;
                vars.tokenId = 0;
                vars.unstakeNftSize = 0;
                vars.totalWithdrawn = 0;
                vars.stakedApeCoin = 0;
                vars.pendingRewards = 0;
                for (uint256 i = 0; i < nftVault.totalStakingNft(mayc, address(staker)); i++) {
                    vars.tokenId = nftVault.stakingNftIdByIndex(mayc, address(staker), i);
                    vars.stakedApeCoin = apeCoinStaking
                        .nftPosition(ApeStakingLib.MAYC_POOL_ID, vars.tokenId)
                        .stakedAmount;

                    vars.pendingRewards = apeCoinStaking.pendingRewards(ApeStakingLib.MAYC_POOL_ID, vars.tokenId);
                    vars.pendingRewards -= staker.calculateFee(vars.pendingRewards);

                    vars.totalWithdrawn += vars.stakedApeCoin;
                    vars.totalWithdrawn += vars.pendingRewards;

                    vars.unstakeNftSize += 1;

                    if (vars.totalWithdrawn >= vars.margin) {
                        break;
                    }
                }
                if (vars.unstakeNftSize > 0) {
                    uint256[] memory tokenIds = new uint256[](vars.unstakeNftSize);
                    for (uint256 i = 0; i < vars.unstakeNftSize; i++) {
                        tokenIds[i] = nftVault.stakingNftIdByIndex(mayc, address(staker), i);
                    }
                    staker.unstakeMayc(tokenIds);
                    vars.changedBalance = _changedBalance(address(coinPool), vars.initBalance);
                }
            }
        }

        // 6. unstake bakc
        if (vars.changedBalance < required) {
            vars.stakedApeCoin = staker.stakedApeCoin(ApeStakingLib.BAKC_POOL_ID);
            if (vars.stakedApeCoin > 0) {
                vars.margin = required - vars.changedBalance;
                vars.tokenId = 0;
                vars.unstakeNftSize = 0;
                vars.totalWithdrawn = 0;
                vars.stakedApeCoin = 0;
                vars.pendingRewards = 0;
                for (uint256 i = 0; i < nftVault.totalStakingNft(bakc, address(staker)); i++) {
                    vars.tokenId = nftVault.stakingNftIdByIndex(bakc, address(staker), i);
                    vars.stakedApeCoin = apeCoinStaking
                        .nftPosition(ApeStakingLib.BAKC_POOL_ID, vars.tokenId)
                        .stakedAmount;

                    vars.pendingRewards = apeCoinStaking.pendingRewards(ApeStakingLib.BAKC_POOL_ID, vars.tokenId);
                    vars.pendingRewards -= staker.calculateFee(vars.pendingRewards);

                    vars.totalWithdrawn += vars.stakedApeCoin;
                    vars.totalWithdrawn += vars.pendingRewards;
                    vars.unstakeNftSize += 1;

                    if (vars.totalWithdrawn >= vars.margin) {
                        break;
                    }
                }
                if (vars.unstakeNftSize > 0) {
                    uint256[] memory tokenIds = new uint256[](vars.unstakeNftSize);
                    for (uint256 i = 0; i < vars.unstakeNftSize; i++) {
                        tokenIds[i] = nftVault.stakingNftIdByIndex(bakc, address(staker), i);
                    }
                    staker.unstakeBakc(tokenIds);
                    vars.changedBalance = _changedBalance(address(coinPool), vars.initBalance);
                }
            }
        }

        withdrawn = vars.changedBalance;
    }

    function _changedBalance(address recipient_, uint256 initBalance_) internal view returns (uint256) {
        return wrapApeCoin.balanceOf(recipient_) - initBalance_;
    }
}
