// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IRewardsStrategy} from "../interfaces/IRewardsStrategy.sol";

contract DefaultRewardsStrategy is IRewardsStrategy, Ownable {
    uint256 internal _nftShare;

    constructor(uint256 nftShare_) Ownable() {
        _nftShare = nftShare_;
    }

    function setNftRewardsShare(uint256 nftShare_) public onlyOwner {
        _nftShare = nftShare_;
    }

    function getNftRewardsShare() public view override returns (uint256 nftShare) {
        return _nftShare;
    }
}
