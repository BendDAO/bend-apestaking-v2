// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * @title MintableERC721
 * @dev ERC721 minting logic
 */
contract MintableERC721 is ERC721Enumerable {
    string public baseURI;
    mapping(uint256 => bool) public lockedTokens;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        baseURI = "https://MintableERC721/";
    }

    /**
     * @dev Function to mint tokens
     * @param tokenId The id of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(uint256 tokenId) public returns (bool) {
        require(tokenId < 10000, "exceed mint limit");

        _mint(_msgSender(), tokenId);
        return true;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory baseURI_) public {
        baseURI = baseURI_;
    }

    function readWithCallback(
        uint256[] calldata tokenIds,
        uint32[] calldata eids,
        uint128 callbackGasLimit
    ) external payable returns (bytes32) {
        require(tokenIds.length == eids.length, "length mismatch");
        require(tokenIds.length > 0, "empty tokenIds");
        require(eids.length > 0, "empty eids");
        callbackGasLimit;

        bytes32[] memory results = new bytes32[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            results[i] = bytes32(tokenIds[i]);
        }

        return keccak256(abi.encodePacked(results));
    }

    function locked(uint256 tokenId) external view returns (bool) {
        return lockedTokens[tokenId];
    }
}
