// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {IBendApeCoinV1} from "../misc/interfaces/IBendApeCoinV1.sol";

contract MockBendApeCoinV1 is IBendApeCoinV1, ERC4626 {
    uint256 public constant REWARDS_AMOUNT = 100 * 1e18;

    constructor(IERC20 asset_) ERC20("BendDAO Staked APE", "bstAPE") ERC4626(asset_) {}

    function assetBalanceOf(address account) external view override returns (uint256) {
        return convertToAssets(balanceOf(account));
    }
}
