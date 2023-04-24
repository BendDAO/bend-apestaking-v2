// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {INftVault} from "../interfaces/INftVault.sol";

import {StNft, IERC721Metadata} from "./StNft.sol";

contract StBAYC is StNft {
    constructor(IERC721Metadata bayc_, INftVault nftVault_) StNft(bayc_, nftVault_, "stBAYC", "Staked BAYC") {}
}
