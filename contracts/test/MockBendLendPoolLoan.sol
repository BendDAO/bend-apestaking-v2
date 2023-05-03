// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ILendPoolLoan} from "../misc/interfaces/ILendPoolLoan.sol";

contract MockBendLendPoolLoan is ILendPoolLoan {
    struct LoanData {
        address borrower;
        address reserveAsset;
        uint256 totalDebt;
        uint256 bidFine;
    }

    mapping(address => mapping(uint256 => uint256)) private _loanIds;
    mapping(uint256 => LoanData) private _loanDatas;
    uint256 private _loanId;

    function setLoanData(
        address nftAsset,
        uint256 nftTokenId,
        address borrower,
        address reserveAsset,
        uint256 totalDebt
    ) public {
        uint256 loanId = _loanIds[nftAsset][nftTokenId];
        if (loanId == 0) {
            loanId = ++_loanId;
            _loanIds[nftAsset][nftTokenId] = loanId;
            _loanDatas[loanId] = LoanData(borrower, reserveAsset, totalDebt, 0);
        } else {
            _loanDatas[loanId] = LoanData(borrower, reserveAsset, totalDebt, 0);
        }
    }

    function setBidFine(uint256 loanId, uint256 bidFine) public {
        _loanDatas[loanId].bidFine = bidFine;
    }

    function setTotalDebt(uint256 loanId, uint256 totalDebt) public {
        _loanDatas[loanId].totalDebt = totalDebt;
    }

    function deleteLoanData(address nftAsset, uint256 nftTokenId) public {
        uint256 loanId = _loanIds[nftAsset][nftTokenId];
        delete _loanIds[nftAsset][nftTokenId];
        delete _loanDatas[loanId];
    }

    function getLoanData(uint256 loanId)
        public
        view
        returns (
            address borrower,
            address reserveAsset,
            uint256 totalDebt,
            uint256 bidFine
        )
    {
        LoanData memory loanData = _loanDatas[loanId];
        borrower = loanData.borrower;
        reserveAsset = loanData.reserveAsset;
        totalDebt = loanData.totalDebt;
        bidFine = loanData.bidFine;
    }

    function getCollateralLoanId(address nftAsset, uint256 nftTokenId) public view returns (uint256) {
        return _loanIds[nftAsset][nftTokenId];
    }

    function borrowerOf(uint256 loanId) public view returns (address) {
        return _loanDatas[loanId].borrower;
    }
}
