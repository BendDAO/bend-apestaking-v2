// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import {IYugaVault} from "../interfaces/IYugaVault.sol";

import {StYugaNFT, IERC721Metadata} from "./StYugaNFT.sol";

contract StMAYC is StYugaNFT {
    constructor(IERC721Metadata mayc_, IYugaVault yugaVault_) StYugaNFT(mayc_, yugaVault_, "stMAYC", "Staked MAYC") {}
}
