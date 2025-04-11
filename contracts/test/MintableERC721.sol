// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * @title MintableERC721
 * @dev ERC721 minting logic
 */
contract MintableERC721 is ERC721Enumerable, Ownable {
    string public baseURI;
    mapping(address => uint256) public mintCounts;
    uint256 maxSupply;
    uint256 maxTokenId;
    mapping(uint256 => bool) public lockedTokens;

    constructor(string memory name, string memory symbol) Ownable() ERC721(name, symbol) {
        maxSupply = 10000;
        maxTokenId = maxSupply - 1;
        baseURI = "https://MintableERC721/";
    }

    /**
     * @dev Function to mint tokens
     * @param tokenId The id of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(uint256 tokenId) public returns (bool) {
        require(tokenId <= maxTokenId, "exceed max token id");
        require(totalSupply() + 1 <= maxSupply, "exceed max supply");

        mintCounts[_msgSender()] += 1;
        require(mintCounts[_msgSender()] <= 100, "exceed mint limit");

        _mint(_msgSender(), tokenId);
        return true;
    }

    function privateMint(uint256 tokenId) public onlyOwner returns (bool) {
        require(tokenId <= maxTokenId, "exceed max token id");
        require(totalSupply() + 1 <= maxSupply, "exceed max supply");

        _mint(_msgSender(), tokenId);
        return true;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }

    function setMaxSupply(uint256 maxSupply_) public onlyOwner {
        maxSupply = maxSupply_;
    }

    function setMaxTokenId(uint256 maxTokenId_) public onlyOwner {
        maxTokenId = maxTokenId_;
    }

    function readWithCallback(
        uint256[] calldata tokenIds,
        uint32[] calldata eids,
        uint128 callbackGasLimit
    ) public payable returns (bytes32) {
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

    function locked(uint256 tokenId) public view returns (bool) {
        return lockedTokens[tokenId];
    }

    function setLocked(uint256 tokenId, bool flag) public {
        lockedTokens[tokenId] = flag;
    }
}
