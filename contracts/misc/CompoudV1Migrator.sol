// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

import {IBendApeCoinV1} from "./interfaces/IBendApeCoinV1.sol";
import {IStakeManagerV1} from "./interfaces/IStakeManagerV1.sol";
import {ICoinPool} from "../interfaces/ICoinPool.sol";

contract CompoudV1Migrator is ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public apeCoin;
    IStakeManagerV1 public stakeManagerV1;
    IBendApeCoinV1 public coinPoolV1;
    ICoinPool public coinPoolV2;

    function initialize(
        address apeCoin_,
        address stakeManagerV1_,
        address coinPoolV1_,
        address coinPoolV2_
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        apeCoin = IERC20Upgradeable(apeCoin_);
        stakeManagerV1 = IStakeManagerV1(stakeManagerV1_);
        coinPoolV1 = IBendApeCoinV1(coinPoolV1_);
        coinPoolV2 = ICoinPool(coinPoolV2_);

        apeCoin.approve(address(coinPoolV2), type(uint256).max);
    }

    function claimV1AndDeposit(address[] calldata proxies) public whenNotPaused nonReentrant returns (uint256 shares) {
        address userStaker = msg.sender;

        // claim rewards from v1 staking
        uint256 apeBalanceBefore = apeCoin.balanceOf(userStaker);
        for (uint256 i = 0; i < proxies.length; i++) {
            stakeManagerV1.claimFor(proxies[i], userStaker);
        }
        uint256 rewards = apeCoin.balanceOf(userStaker) - apeBalanceBefore;
        require(rewards > 0, "CompoudV1Migrator: no rewards in v1");

        // deposit rewards to v2 staking
        uint256 v2SharesBefore = coinPoolV2.balanceOf(userStaker);

        apeCoin.safeTransferFrom(userStaker, address(this), rewards);
        shares = coinPoolV2.deposit(rewards, userStaker);
        require(shares > 0, "CompoudV1Migrator: deposit into v2 but return zero shares");

        uint256 v2SharesAfter = coinPoolV2.balanceOf(userStaker);
        require((v2SharesBefore + shares) == v2SharesAfter, "CompoudV1Migrator: shares mismatch");
    }

    function withdrawV1AndDeposit() public whenNotPaused nonReentrant returns (uint256 shares) {
        address userStaker = msg.sender;

        // withdraw coins from v1 staking
        uint256 v1Assets = coinPoolV1.assetBalanceOf(userStaker);
        require(v1Assets > 0, "CompoudV1Migrator: no assets in v1");

        uint256 v1Shares = coinPoolV1.withdraw(v1Assets, address(this), userStaker);
        require(v1Shares > 0, "CompoudV1Migrator: withdraw from v1 but return zero shares");

        // deposit coins to v2 staking
        uint256 v2SharesBefore = coinPoolV2.balanceOf(userStaker);

        shares = coinPoolV2.deposit(v1Assets, userStaker);
        require(shares > 0, "CompoudV1Migrator: deposit into v2 but return zero shares");

        uint256 v2SharesAfter = coinPoolV2.balanceOf(userStaker);
        require((v2SharesBefore + shares) == v2SharesAfter, "CompoudV1Migrator: shares mismatch");
    }
}
