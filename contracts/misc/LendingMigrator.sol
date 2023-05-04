// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import {IAaveLendPoolAddressesProvider} from "./interfaces/IAaveLendPoolAddressesProvider.sol";
import {IAaveLendPool} from "./interfaces/IAaveLendPool.sol";
import {IAaveFlashLoanReceiver} from "./interfaces/IAaveFlashLoanReceiver.sol";
import {ILendPoolAddressesProvider} from "./interfaces/ILendPoolAddressesProvider.sol";
import {ILendPool} from "./interfaces/ILendPool.sol";
import {ILendPoolLoan} from "./interfaces/ILendPoolLoan.sol";

import {IStakedNft} from "../interfaces/IStakedNft.sol";
import {INftPool} from "../interfaces/INftPool.sol";

contract LendingMigrator is IAaveFlashLoanReceiver, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    IAaveLendPoolAddressesProvider public aaveAddressesProvider;
    IAaveLendPool public aaveLendPool;
    ILendPoolAddressesProvider public bendAddressesProvider;
    ILendPool public bendLendPool;
    ILendPoolLoan public bendLendLoan;

    INftPool public nftPool;
    IStakedNft public stBayc;
    IStakedNft public stMayc;
    IStakedNft public stBakc;

    IERC721Upgradeable public bayc;
    IERC721Upgradeable public mayc;
    IERC721Upgradeable public bakc;

    function initialize(
        address aaveAddressesProvider_,
        address bendAddressesProvider_,
        address nftPool_,
        address stBayc_,
        address stMayc_,
        address stBakc_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        nftPool = INftPool(nftPool_);
        stBayc = IStakedNft(stBayc_);
        stMayc = IStakedNft(stMayc_);
        stBakc = IStakedNft(stBakc_);

        bayc = IERC721Upgradeable(stBayc.underlyingAsset());
        mayc = IERC721Upgradeable(stMayc.underlyingAsset());
        bakc = IERC721Upgradeable(stBakc.underlyingAsset());

        aaveAddressesProvider = IAaveLendPoolAddressesProvider(aaveAddressesProvider_);
        aaveLendPool = IAaveLendPool(aaveAddressesProvider.getLendingPool());

        bendAddressesProvider = ILendPoolAddressesProvider(bendAddressesProvider_);
        bendLendPool = ILendPool(bendAddressesProvider.getLendPool());
        bendLendLoan = ILendPoolLoan(bendAddressesProvider.getLendPoolLoan());

        IERC721Upgradeable(bayc).setApprovalForAll(address(nftPool), true);
        IERC721Upgradeable(mayc).setApprovalForAll(address(nftPool), true);
        IERC721Upgradeable(bakc).setApprovalForAll(address(nftPool), true);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address /*initiator*/,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(aaveLendPool), "Migrator: caller must be aave lending pool");
        require(
            assets.length == 1 && amounts.length == 1 && premiums.length == 1,
            "Migrator: multiple assets not supported"
        );

        (address[] memory nftAssets, uint256[] memory nftTokenIds) = abi.decode(params, (address[], uint256[]));
        require(nftAssets.length == nftTokenIds.length, "Migrator: inconsistent assets and token ids");

        uint256 aaveFlashLoanFeeRatio = aaveLendPool.FLASHLOAN_PREMIUM_TOTAL();

        IERC20Upgradeable(assets[0]).approve(address(bendLendPool), type(uint256).max);

        for (uint256 i = 0; i < nftTokenIds.length; i++) {
            RepayAndBorrowLocaVars memory vars;
            vars.nftAsset = nftAssets[i];
            vars.nftTokenId = nftTokenIds[i];
            vars.flashLoanAsset = assets[0];
            vars.flashLoanFeeRatio = aaveFlashLoanFeeRatio;

            _repayAndBorrowPerNft(vars);
        }

        IERC20Upgradeable(assets[0]).approve(address(bendLendPool), 0);

        IERC20Upgradeable(assets[0]).approve(msg.sender, (amounts[0] + premiums[0]));

        return true;
    }

    struct RepayAndBorrowLocaVars {
        address nftAsset;
        uint256 nftTokenId;
        address flashLoanAsset;
        uint256 flashLoanFeeRatio;
        uint256 loanId;
        address borrower;
        address debtReserve;
        uint256 debtTotalAmount;
        uint256 debtRemainAmount;
        uint256 redeemAmount;
        uint256 bidFine;
        uint256 debtTotalAmountWithBidFine;
        uint256 balanceBeforeRepay;
        uint256[] nftTokenIds;
        uint256 flashLoanPremium;
        uint256 debtBorrowAmountWithFee;
        uint256 balanceBeforeBorrow;
        uint256 balanceAfterBorrow;
    }

    function _repayAndBorrowPerNft(RepayAndBorrowLocaVars memory vars) internal {
        (vars.loanId, , , , vars.bidFine) = bendLendPool.getNftAuctionData(vars.nftAsset, vars.nftTokenId);
        (, vars.debtReserve, , vars.debtTotalAmount, , ) = bendLendPool.getNftDebtData(vars.nftAsset, vars.nftTokenId);
        vars.debtTotalAmountWithBidFine = vars.debtTotalAmount + vars.bidFine;

        vars.borrower = bendLendLoan.borrowerOf(vars.loanId);
        vars.balanceBeforeRepay = IERC20Upgradeable(vars.debtReserve).balanceOf(address(this));

        require(vars.debtReserve == vars.flashLoanAsset, "Migrator: invalid flash loan asset");
        require(vars.debtTotalAmountWithBidFine <= vars.balanceBeforeRepay, "Migrator: insufficent to repay debt");

        // redeem first if nft is in auction
        if (vars.bidFine > 0) {
            vars.redeemAmount = (vars.debtTotalAmount * 2) / 3;
            bendLendPool.redeem(vars.nftAsset, vars.nftTokenId, vars.redeemAmount, vars.bidFine);

            (, , , vars.debtRemainAmount, , ) = bendLendPool.getNftDebtData(vars.nftAsset, vars.nftTokenId);
        } else {
            vars.debtRemainAmount = vars.debtTotalAmount;
        }

        // repay all the old debt
        bendLendPool.repay(vars.nftAsset, vars.nftTokenId, vars.debtRemainAmount);

        // stake original nft to the staking pool
        IERC721Upgradeable(vars.nftAsset).safeTransferFrom(vars.borrower, address(address(this)), vars.nftTokenId);
        vars.nftTokenIds = new uint256[](1);
        vars.nftTokenIds[0] = vars.nftTokenId;
        nftPool.deposit(vars.nftAsset, vars.nftTokenIds);

        // borrow new debt with the staked nft
        vars.balanceBeforeBorrow = IERC20Upgradeable(vars.debtReserve).balanceOf(address(this));

        IStakedNft stNftAsset = getStakedNFTAsset(vars.nftAsset);
        IERC721Upgradeable(address(stNftAsset)).approve(address(bendLendPool), vars.nftTokenId);

        vars.flashLoanPremium = (vars.debtTotalAmountWithBidFine * vars.flashLoanFeeRatio) / 10000;
        vars.debtBorrowAmountWithFee = vars.debtTotalAmountWithBidFine + vars.flashLoanPremium;
        bendLendPool.borrow(
            vars.debtReserve,
            vars.debtBorrowAmountWithFee,
            address(stNftAsset),
            vars.nftTokenId,
            vars.borrower,
            0
        );

        vars.balanceAfterBorrow = IERC20Upgradeable(vars.debtReserve).balanceOf(address(this));
        require(vars.balanceAfterBorrow == (vars.balanceBeforeBorrow + vars.debtBorrowAmountWithFee));
    }

    function getStakedNFTAsset(address nftAsset) internal view returns (IStakedNft) {
        if (nftAsset == address(bayc)) {
            return stBayc;
        } else if (nftAsset == address(mayc)) {
            return stMayc;
        } else if (nftAsset == address(bakc)) {
            return stBakc;
        } else {
            revert("Migrator: invalid nft asset");
        }
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
