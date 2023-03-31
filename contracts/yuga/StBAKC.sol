// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import {IYugaVault} from "../interfaces/IYugaVault.sol";

import {StYugaNFT, IERC721Metadata} from "./StYugaNFT.sol";

contract StBAKC is StYugaNFT {
    constructor(IERC721Metadata bakc_, IYugaVault yugaVault_) StYugaNFT(bakc_, yugaVault_, "stBAKC", "Staked BAKC") {}
}
