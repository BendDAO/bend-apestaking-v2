// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ILendPoolAddressesProvider} from "../misc/interfaces/ILendPoolAddressesProvider.sol";
import {ILendPool} from "../misc/interfaces/ILendPool.sol";

import "./MockBendLendPoolLoan.sol";

contract MockBendLendPool is ILendPool {
    ILendPoolAddressesProvider public addressesProvider;

    function setAddressesProvider(address addressesProvider_) public {
        addressesProvider = ILendPoolAddressesProvider(addressesProvider_);
    }

    function borrow(
        address reserveAsset,
        uint256 amount,
        address nftAsset,
        uint256 nftTokenId,
        address /*onBehalfOf*/,
        uint16 /*referralCode*/
    ) external {
        MockBendLendPoolLoan lendPoolLoan = MockBendLendPoolLoan(
            ILendPoolAddressesProvider(addressesProvider).getLendPoolLoan()
        );
        lendPoolLoan.setLoanData(nftAsset, nftTokenId, msg.sender, reserveAsset, amount);

        IERC721(nftAsset).transferFrom(msg.sender, address(this), nftTokenId);
        IERC20(reserveAsset).transfer(msg.sender, amount);
    }

    function repay(address nftAsset, uint256 nftTokenId, uint256 amount) external returns (uint256, bool) {
        MockBendLendPoolLoan lendPoolLoan = MockBendLendPoolLoan(
            ILendPoolAddressesProvider(addressesProvider).getLendPoolLoan()
        );

        uint256 loanId = lendPoolLoan.getCollateralLoanId(nftAsset, nftTokenId);

        (address borrower, address reserveAsset, uint256 totalDebt, uint256 bidFineInLoan) = lendPoolLoan.getLoanData(
            loanId
        );
        require(bidFineInLoan == 0, "loan is in auction");

        if (amount > totalDebt) {
            amount = totalDebt;
        }
        totalDebt -= amount;
        lendPoolLoan.setTotalDebt(loanId, totalDebt);

        IERC20(reserveAsset).transferFrom(msg.sender, address(this), amount);

        if (totalDebt == 0) {
            IERC721(nftAsset).transferFrom(address(this), borrower, nftTokenId);
        }

        return (amount, true);
    }

    function redeem(address nftAsset, uint256 nftTokenId, uint256 amount, uint256 bidFine) external returns (uint256) {
        MockBendLendPoolLoan lendPoolLoan = MockBendLendPoolLoan(
            ILendPoolAddressesProvider(addressesProvider).getLendPoolLoan()
        );
        uint256 loanId = lendPoolLoan.getCollateralLoanId(nftAsset, nftTokenId);

        (, address reserveAsset, uint256 totalDebt, uint256 bidFineInLoan) = lendPoolLoan.getLoanData(loanId);
        uint256 maxRedeemAmount = (totalDebt * 9) / 10;
        require(amount <= maxRedeemAmount, "exceed max redeem amount");
        require(bidFine == bidFineInLoan, "insufficient bid fine");

        IERC20(reserveAsset).transferFrom(msg.sender, address(this), (amount + bidFine));

        totalDebt -= amount;
        lendPoolLoan.setTotalDebt(loanId, totalDebt);
        lendPoolLoan.setBidFine(loanId, 0);

        return amount;
    }

    function getNftDebtData(
        address nftAsset,
        uint256 nftTokenId
    )
        external
        view
        returns (
            uint256 loanId,
            address reserveAsset,
            uint256 totalCollateral,
            uint256 totalDebt,
            uint256 availableBorrows,
            uint256 healthFactor
        )
    {
        MockBendLendPoolLoan lendPoolLoan = MockBendLendPoolLoan(
            ILendPoolAddressesProvider(addressesProvider).getLendPoolLoan()
        );

        loanId = lendPoolLoan.getCollateralLoanId(nftAsset, nftTokenId);
        (, reserveAsset, totalDebt, ) = lendPoolLoan.getLoanData(loanId);

        totalCollateral = totalDebt;
        availableBorrows = 0;
        healthFactor = 1e18;
    }

    function getNftAuctionData(
        address nftAsset,
        uint256 nftTokenId
    )
        external
        view
        returns (uint256 loanId, address bidderAddress, uint256 bidPrice, uint256 bidBorrowAmount, uint256 bidFine)
    {
        MockBendLendPoolLoan lendPoolLoan = MockBendLendPoolLoan(
            ILendPoolAddressesProvider(addressesProvider).getLendPoolLoan()
        );

        loanId = lendPoolLoan.getCollateralLoanId(nftAsset, nftTokenId);

        (, , bidBorrowAmount, bidFine) = lendPoolLoan.getLoanData(loanId);

        bidderAddress = msg.sender;
        bidPrice = (bidBorrowAmount * 105) / 100;
    }
}
