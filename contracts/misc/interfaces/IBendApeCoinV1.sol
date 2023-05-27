// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IBendApeCoinV1 is IERC4626 {
    function assetBalanceOf(address account) external view returns (uint256);
}
