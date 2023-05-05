// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/**
 * @title MintableERC721
 * @dev ERC721 minting logic
 */
contract MockBNFT is ERC721Enumerable, ERC721Holder {
    string public baseURI;
    address public underlyingAsset;

    constructor(string memory name, string memory symbol, address underlyingAsset_) ERC721(name, symbol) {
        baseURI = "https://MockBNFT/";
        underlyingAsset = underlyingAsset_;
    }

    function mint(address to, uint256 tokenId) external {
        IERC721Enumerable(underlyingAsset).safeTransferFrom(_msgSender(), address(this), tokenId);

        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        require(_msgSender() == ownerOf(tokenId), "MockBNFT: not owner");

        _burn(tokenId);

        IERC721Enumerable(underlyingAsset).safeTransferFrom(address(this), _msgSender(), tokenId);
    }
}
