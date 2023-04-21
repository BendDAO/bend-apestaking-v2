// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {INftVault} from "../interfaces/INftVault.sol";

import {StNft, IERC721Metadata} from "./StNft.sol";

contract StMAYC is StNft {
    constructor(IERC721Metadata mayc_, INftVault nftVault_) StNft(mayc_, nftVault_, "stMAYC", "Staked MAYC") {}
}
