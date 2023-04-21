// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {INftVault} from "../interfaces/INftVault.sol";

import {StNft, IERC721Metadata} from "./StNft.sol";

contract StBAKC is StNft {
    constructor(IERC721Metadata bakc_, INftVault nftVault_) StNft(bakc_, nftVault_, "stBAKC", "Staked BAKC") {}
}
