// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
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

contract LendingMigrator is
    IAaveFlashLoanReceiver,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    event NftMigrated(address indexed borrower, address indexed nftAsset, uint256 nftTokenId, uint256 debtAmount);

    uint256 public constant PERCENTAGE_FACTOR = 1e4;
    uint256 public constant BORROW_SLIPPAGE = 10; // 0.1%

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
        __Pausable_init();

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

        IERC721Upgradeable(address(stBayc)).setApprovalForAll(address(bendLendPool), true);
        IERC721Upgradeable(address(stMayc)).setApprovalForAll(address(bendLendPool), true);
        IERC721Upgradeable(address(stBakc)).setApprovalForAll(address(bendLendPool), true);
    }

    struct ExecuteOperationLocaVars {
        address[] nftAssets;
        uint256[] nftTokenIds;
        uint256[] newDebtAmounts;
        address borrower;
        uint256 aaveFlashLoanFeeRatio;
        uint256 totalNewDebtAmount;
        uint256 balanceBeforeMigrate;
        uint256 balanceDiffBeforeMigrate;
        uint256 balanceAfterMigrate;
        uint256 balanceDiffAfterMigrate;
        uint256 balanceDiffToUser;
        uint256 repayToAave;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address /*initiator*/,
        bytes calldata params
    ) external whenNotPaused nonReentrant returns (bool) {
        ExecuteOperationLocaVars memory execVars;

        require(msg.sender == address(aaveLendPool), "Migrator: caller must be aave lending pool");
        require(
            assets.length == 1 && amounts.length == 1 && premiums.length == 1,
            "Migrator: multiple assets not supported"
        );

        (execVars.nftAssets, execVars.nftTokenIds, execVars.newDebtAmounts) = abi.decode(
            params,
            (address[], uint256[], uint256[])
        );
        require(execVars.nftTokenIds.length > 0, "Migrator: empty token ids");
        require(
            execVars.nftAssets.length == execVars.nftTokenIds.length,
            "Migrator: inconsistent assets and token ids"
        );
        require(
            execVars.nftAssets.length == execVars.newDebtAmounts.length,
            "Migrator: inconsistent assets and debt amounts"
        );

        execVars.aaveFlashLoanFeeRatio = aaveLendPool.FLASHLOAN_PREMIUM_TOTAL();

        IERC20Upgradeable(assets[0]).approve(address(bendLendPool), type(uint256).max);

        execVars.balanceBeforeMigrate = IERC20Upgradeable(assets[0]).balanceOf(address(this));
        execVars.balanceDiffBeforeMigrate = execVars.balanceBeforeMigrate - amounts[0];

        for (uint256 i = 0; i < execVars.nftTokenIds.length; i++) {
            RepayAndBorrowLocaVars memory vars;
            vars.nftAsset = execVars.nftAssets[i];
            vars.nftTokenId = execVars.nftTokenIds[i];
            vars.newDebtAmount = execVars.newDebtAmounts[i];
            vars.flashLoanAsset = assets[0];
            vars.flashLoanFeeRatio = execVars.aaveFlashLoanFeeRatio;

            execVars.totalNewDebtAmount += vars.newDebtAmount;

            _repayAndBorrowPerNft(execVars, vars);
        }

        require(execVars.totalNewDebtAmount == amounts[0], "Migrator: inconsistent total debt amount");

        IERC20Upgradeable(assets[0]).approve(address(bendLendPool), 0);

        execVars.repayToAave = amounts[0] + premiums[0];
        IERC20Upgradeable(assets[0]).approve(msg.sender, execVars.repayToAave);

        execVars.balanceAfterMigrate = IERC20Upgradeable(assets[0]).balanceOf(address(this));
        require(execVars.balanceAfterMigrate >= execVars.repayToAave, "Migrator: insufficent to repay aave");

        // we try to borrow a little more to make sure it has enough to repay flash loan
        // but remain part need to be returned to user
        execVars.balanceDiffAfterMigrate = execVars.balanceAfterMigrate - execVars.repayToAave;
        if (execVars.balanceDiffAfterMigrate > execVars.balanceDiffBeforeMigrate) {
            execVars.balanceDiffToUser = execVars.balanceDiffAfterMigrate - execVars.balanceDiffBeforeMigrate;
            IERC20Upgradeable(assets[0]).transfer(execVars.borrower, execVars.balanceDiffToUser);
        }

        return true;
    }

    struct RepayAndBorrowLocaVars {
        address nftAsset;
        uint256 nftTokenId;
        uint256 newDebtAmount;
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
        uint256 loanIdForStNft;
        address borrowerForStNft;
    }

    function _repayAndBorrowPerNft(
        ExecuteOperationLocaVars memory execVars,
        RepayAndBorrowLocaVars memory vars
    ) internal {
        (vars.loanId, , , , vars.bidFine) = bendLendPool.getNftAuctionData(vars.nftAsset, vars.nftTokenId);
        (, vars.debtReserve, , vars.debtTotalAmount, , ) = bendLendPool.getNftDebtData(vars.nftAsset, vars.nftTokenId);
        vars.debtTotalAmountWithBidFine = vars.debtTotalAmount + vars.bidFine;

        // check new debt can cover old debt and flash loan fee
        vars.flashLoanPremium = (vars.newDebtAmount * vars.flashLoanFeeRatio) / PERCENTAGE_FACTOR;
        vars.debtBorrowAmountWithFee = vars.debtTotalAmountWithBidFine + vars.flashLoanPremium;
        require(
            vars.debtBorrowAmountWithFee <= vars.newDebtAmount,
            "Migrator: new debt can not cover old debt with fee"
        );

        // check borrower is same
        vars.borrower = bendLendLoan.borrowerOf(vars.loanId);
        if (execVars.borrower == address(0)) {
            execVars.borrower = vars.borrower;
        } else {
            require(execVars.borrower == vars.borrower, "Migrator: borrower not same");
        }

        vars.balanceBeforeRepay = IERC20Upgradeable(vars.debtReserve).balanceOf(address(this));

        require(vars.debtReserve == vars.flashLoanAsset, "Migrator: invalid flash loan asset");
        require(vars.debtTotalAmountWithBidFine <= vars.balanceBeforeRepay, "Migrator: insufficent to repay old debt");

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
        address[] memory nfts = new address[](1);
        nfts[0] = vars.nftAsset;
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = vars.nftTokenIds;
        nftPool.deposit(nfts, tokenIds);

        // borrow new debt with the staked nft
        vars.balanceBeforeBorrow = IERC20Upgradeable(vars.debtReserve).balanceOf(address(this));

        IStakedNft stNftAsset = getStakedNFTAsset(vars.nftAsset);

        bendLendPool.borrow(
            vars.debtReserve,
            vars.newDebtAmount,
            address(stNftAsset),
            vars.nftTokenId,
            vars.borrower,
            0
        );

        vars.balanceAfterBorrow = IERC20Upgradeable(vars.debtReserve).balanceOf(address(this));
        require(
            vars.balanceAfterBorrow == (vars.balanceBeforeBorrow + vars.newDebtAmount),
            "Migrator: balance wrong after borrow"
        );

        vars.loanIdForStNft = bendLendLoan.getCollateralLoanId(address(stNftAsset), vars.nftTokenId);
        vars.borrowerForStNft = bendLendLoan.borrowerOf(vars.loanIdForStNft);
        require(vars.borrowerForStNft == vars.borrower, "Migrator: stnft borrower not same");

        emit NftMigrated(vars.borrower, vars.nftAsset, vars.nftTokenId, vars.debtTotalAmount);
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
