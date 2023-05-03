// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ILendPoolAddressesProvider} from "../misc/interfaces/ILendPoolAddressesProvider.sol";

contract MockBendLendPoolAddressesProvider is ILendPoolAddressesProvider {
    address public lendPool;
    address public lendPoolLoan;

    function setLendPool(address lendPool_) public {
        lendPool = lendPool_;
    }

    function setLendPoolLoan(address lendPoolLoan_) public {
        lendPoolLoan = lendPoolLoan_;
    }

    function getLendPool() public view returns (address) {
        return lendPool;
    }

    function getLendPoolLoan() public view returns (address) {
        return lendPoolLoan;
    }
}
