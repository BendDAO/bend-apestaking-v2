// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {IBNFTRegistry} from "../interfaces/IBNFTRegistry.sol";

contract MockBNFTRegistry is IBNFTRegistry {
    mapping(address => address) public bnftContracts;

    function getBNFTAddresses(address nftAsset) public view returns (address bNftProxy, address bNftImpl) {
        bNftProxy = bnftContracts[nftAsset];
        bNftImpl = bNftProxy;
    }

    function setBNFTContract(address nftAsset, address bnftAsset) public {
        bnftContracts[nftAsset] = bnftAsset;
    }
}
