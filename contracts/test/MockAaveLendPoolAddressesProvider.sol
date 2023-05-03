// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IAaveLendPoolAddressesProvider} from "../misc/interfaces/IAaveLendPoolAddressesProvider.sol";

contract MocKAaveLendPoolAddressesProvider is IAaveLendPoolAddressesProvider {
    address public lendingPool;

    function setLendingPool(address lendingPool_) public {
        lendingPool = lendingPool_;
    }

    function getLendingPool() public view returns (address) {
        return lendingPool;
    }
}
