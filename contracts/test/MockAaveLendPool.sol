// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAaveLendPool} from "../misc/interfaces/IAaveLendPool.sol";
import {IAaveFlashLoanReceiver} from "../misc/interfaces/IAaveFlashLoanReceiver.sol";

contract MockAaveLendPool is IAaveLendPool {
    uint256 private _flashLoanPremiumTotal;

    constructor() {
        _flashLoanPremiumTotal = 9;
    }

    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint256) {
        return _flashLoanPremiumTotal;
    }

    struct FlashLoanLocalVars {
        IAaveFlashLoanReceiver receiver;
        uint256 i;
        address currentAsset;
        uint256 currentAmount;
        uint256 currentPremium;
        uint256 currentAmountPlusPremium;
    }

    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata /*modes*/,
        address /*onBehalfOf*/,
        bytes calldata params,
        uint16 /*referralCode*/
    ) external {
        FlashLoanLocalVars memory vars;
        vars.receiver = IAaveFlashLoanReceiver(receiverAddress);

        uint256[] memory premiums = new uint256[](assets.length);

        for (vars.i = 0; vars.i < assets.length; vars.i++) {
            premiums[vars.i] = (amounts[vars.i] * _flashLoanPremiumTotal) / 10000;

            IERC20(assets[vars.i]).transfer(receiverAddress, amounts[vars.i]);
        }

        require(
            vars.receiver.executeOperation(assets, amounts, premiums, msg.sender, params),
            "AaveLendPool: Flashloan execution failed"
        );

        for (vars.i = 0; vars.i < assets.length; vars.i++) {
            vars.currentAsset = assets[vars.i];
            vars.currentAmount = amounts[vars.i];
            vars.currentPremium = premiums[vars.i];
            vars.currentAmountPlusPremium = vars.currentAmount + vars.currentPremium;

            IERC20(vars.currentAsset).transferFrom(receiverAddress, vars.currentAsset, vars.currentAmountPlusPremium);
        }
    }
}
