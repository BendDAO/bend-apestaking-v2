// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;
import {ERC4626Upgradeable, IERC4626Upgradeable, IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IApeCoinStaking} from "./interfaces/IApeCoinStaking.sol";
import {ICoinPool} from "./interfaces/ICoinPool.sol";
import {IStakeManager} from "./interfaces/IStakeManager.sol";

contract BendCoinPool is ICoinPool, ERC4626Upgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IApeCoinStaking public apeCoinStaking;
    IStakeManager public staker;

    uint256 public override pendingApeCoin;

    modifier onlyStaker() {
        require(_msgSender() == address(staker), "BendCoinPool: caller is not staker");
        _;
    }

    function initialize(IApeCoinStaking apeStaking_, IStakeManager staker_) external initializer {
        IERC20MetadataUpgradeable apeCoin = IERC20MetadataUpgradeable(apeStaking_.apeCoin());
        __Ownable_init();
        __ERC20_init("Bend Auto-compund ApeCoin", "bacAPE");
        __ERC4626_init(apeCoin);
        apeCoinStaking = apeStaking_;
        staker = staker_;
    }

    function totalAssets() public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        uint256 amount = pendingApeCoin;
        amount += staker.totalPendingRewards();
        amount += staker.totalStakedApeCoin();
        amount += staker.totalRefund();
        return amount;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override(ERC4626Upgradeable) {
        // transfer ape coin from caller
        super._deposit(caller, receiver, assets, shares);
        // increase pending amount
        pendingApeCoin += assets;
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override(ERC4626Upgradeable) {
        if (pendingApeCoin < assets) {
            uint256 required = assets - pendingApeCoin;
            require(staker.withdrawApeCoin(required) >= (required), "BendCoinPool: withdraw failed");
        }
        // transfer ape coin to receiver
        super._withdraw(caller, receiver, owner, assets, shares);
        // decrease pending amount
        pendingApeCoin -= assets;
    }

    function assetBalanceOf(address account) external view override returns (uint256) {
        return convertToAssets(balanceOf(account));
    }

    function receiveApeCoin(uint256 principalAmount, uint256 rewardsAmount_) external override onlyStaker {
        uint256 totalAmount = principalAmount + rewardsAmount_;
        IERC20Upgradeable(asset()).safeTransferFrom(_msgSender(), address(this), totalAmount);
        pendingApeCoin += totalAmount;
        if (rewardsAmount_ > 0) {
            emit RewardDistributed(rewardsAmount_);
        }
    }

    function pullApeCoin(uint256 amount_) external override onlyStaker {
        pendingApeCoin -= amount_;
        IERC20Upgradeable(asset()).safeTransfer(address(staker), amount_);
    }
}
