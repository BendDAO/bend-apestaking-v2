// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ICoinPool} from "../interfaces/ICoinPool.sol";

contract MockBendStakeManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IERC20Upgradeable public apeCoin;
    ICoinPool public coinPool;
    uint256 public reserved;

    constructor(IERC20Upgradeable apeCoin_, ICoinPool coinPool_, uint256 reserved_) {
        apeCoin = apeCoin_;
        coinPool = coinPool_;
        apeCoin.approve(address(coinPool), type(uint256).max);
        reserved = reserved_;
    }

    function totalStakedApeCoin() external view returns (uint256) {
        return apeCoin.balanceOf(address(this));
    }

    function totalPendingRewards() external pure returns (uint256) {
        return 0;
    }

    function totalRefund() external pure returns (uint256) {
        return 0;
    }

    function withdrawApeCoin(uint256 required) external returns (uint256) {
        if (required >= apeCoin.balanceOf(address(this))) {
            required = apeCoin.balanceOf(address(this)) - reserved;
        }
        uint256 principal = required / 2;
        coinPool.receiveApeCoin(principal, required - principal);
        return required;
    }
}
