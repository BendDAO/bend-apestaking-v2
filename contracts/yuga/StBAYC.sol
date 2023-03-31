// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import {IYugaVault} from "../interfaces/IYugaVault.sol";

import {StYugaNFT, IERC721Metadata} from "./StYugaNFT.sol";

contract StBAYC is StYugaNFT {
    constructor(IERC721Metadata bayc_, IYugaVault yugaVault_) StYugaNFT(bayc_, yugaVault_, "stBAYC", "Staked BAYC") {}
}
