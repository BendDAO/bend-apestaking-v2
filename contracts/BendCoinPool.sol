// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ERC4626Upgradeable, IERC4626Upgradeable, IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IApeCoinStaking} from "./interfaces/IApeCoinStaking.sol";
import {ICoinPool} from "./interfaces/ICoinPool.sol";
import {IStakeManager} from "./interfaces/IStakeManager.sol";

contract BendCoinPool is
    ICoinPool,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC4626Upgradeable
{
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IApeCoinStaking public apeCoinStaking;
    IERC20Upgradeable public apeCoin;
    IStakeManager public staker;

    uint256 public override pendingApeCoin;

    modifier onlyStaker() {
        require(_msgSender() == address(staker), "BendCoinPool: caller is not staker");
        _;
    }

    function initialize(IApeCoinStaking apeStaking_, IStakeManager staker_) external initializer {
        apeCoin = IERC20Upgradeable(apeStaking_.apeCoin());
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("Bend Auto-compound ApeCoin", "bacAPE");
        __ERC4626_init(apeCoin);
        apeCoinStaking = apeStaking_;
        staker = staker_;
    }

    function totalAssets() public view override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        uint256 amount = pendingApeCoin;
        amount += staker.totalStakedApeCoin();
        amount += staker.totalRefund();
        return amount;
    }

    function mintSelf(uint256 shares) external override returns (uint256) {
        return mint(shares, _msgSender());
    }

    function depositSelf(uint256 assets) external override returns (uint256) {
        return deposit(assets, _msgSender());
    }

    function withdrawSelf(uint256 assets) external override returns (uint256) {
        return withdraw(assets, _msgSender(), _msgSender());
    }

    function redeemSelf(uint256 shares) external override returns (uint256) {
        return redeem(shares, _msgSender(), _msgSender());
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");
        _withdrawApeCoin(assets);
        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        pendingApeCoin -= assets;
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override(ERC4626Upgradeable, IERC4626Upgradeable) returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");
        uint256 assets;
        do {
            assets = previewRedeem(shares);
            _withdrawApeCoin(assets);
            // loop calculate & withdraw assets, because the share price may change when `_withdrawApeCoin`
        } while (assets != previewRedeem(shares));
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        pendingApeCoin -= assets;
        return assets;
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override(ERC4626Upgradeable) nonReentrant whenNotPaused {
        // transfer ape coin to receiver
        super._withdraw(caller, receiver, owner, assets, shares);
        // decrease pending amount
        pendingApeCoin -= assets;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override(ERC4626Upgradeable) nonReentrant whenNotPaused {
        // transfer ape coin from caller
        super._deposit(caller, receiver, assets, shares);
        // increase pending amount
        pendingApeCoin += assets;
    }

    function _withdrawApeCoin(uint256 assets) internal {
        if (pendingApeCoin < assets) {
            uint256 required = assets - pendingApeCoin;
            require(staker.withdrawApeCoin(required) >= (required), "BendCoinPool: withdraw failed");
        }
    }

    function assetBalanceOf(address account) external view override returns (uint256) {
        return convertToAssets(balanceOf(account));
    }

    function receiveApeCoin(uint256 principalAmount, uint256 rewardsAmount_) external override onlyStaker {
        uint256 totalAmount = principalAmount + rewardsAmount_;
        apeCoin.safeTransferFrom(_msgSender(), address(this), totalAmount);
        pendingApeCoin += totalAmount;
        if (rewardsAmount_ > 0) {
            emit RewardDistributed(rewardsAmount_);
        }
    }

    function pullApeCoin(uint256 amount_) external override onlyStaker {
        pendingApeCoin -= amount_;
        apeCoin.safeTransfer(address(staker), amount_);
    }

    function setPause(bool flag) public onlyOwner {
        if (flag) {
            _pause();
        } else {
            _unpause();
        }
    }
}
