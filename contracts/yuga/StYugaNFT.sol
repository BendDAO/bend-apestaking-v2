// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";

import {IStakedNFT} from "../interfaces/IStakedNFT.sol";
import {IYugaVault} from "../interfaces/IYugaVault.sol";

abstract contract StYugaNFT is IStakedNFT, ERC721Enumerable, Ownable {
    IERC721Metadata private _yugaNft;
    IYugaVault public _yugaVault;

    // Mapping from staker to list of staked token IDs
    mapping(address => mapping(uint256 => uint256)) private _stakedTokens;

    // Mapping from token ID to index of the staker tokens list
    mapping(uint256 => uint256) private _stakedTokensIndex;

    // Mapping from staker to total staked amount of tokens
    mapping(address => uint256) public totalStaked;

    // Mapping from token ID to minter
    mapping(uint256 => address) public override minterOf;

    constructor(
        IERC721Metadata yugaNft_,
        IYugaVault yugaVault_,
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {
        _yugaNft = yugaNft_;
        _yugaVault = yugaVault_;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC721Enumerable)
        returns (bool)
    {
        return interfaceId == type(IStakedNFT).interfaceId || super.supportsInterface(interfaceId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        require(_msgSender() == address(_yugaNft), "StYugaNFT: nft not acceptable");
        return IERC721Receiver.onERC721Received.selector;
    }

    function mint(
        address staker_,
        address to_,
        uint256 tokenId_
    ) external override {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId_;
        _yugaNft.safeTransferFrom(_msgSender(), address(this), tokenId_);
        _yugaVault.depositNFT(address(_yugaNft), tokenIds, staker_);

        // set minter
        minterOf[tokenId_] = _msgSender();

        _addTokenToStakerEnumeration(staker_, tokenId_);

        _safeMint(to_, tokenId_);
    }

    function mint(
        address staker_,
        address to_,
        uint256[] calldata tokenIds_
    ) external override {
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            _yugaNft.safeTransferFrom(_msgSender(), address(this), tokenIds_[i]);
        }
        _yugaVault.depositNFT(address(_yugaNft), tokenIds_, staker_);
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            // set minter
            minterOf[tokenIds_[i]] = _msgSender();

            _addTokenToStakerEnumeration(staker_, tokenIds_[i]);

            _safeMint(to_, tokenIds_[i]);
        }
    }

    function burn(uint256 tokenId_) external override {
        require(_msgSender() == ownerOf(tokenId_), "sYugaNFT: only owner can burn");
        require(address(_yugaVault) == _yugaNft.ownerOf(tokenId_), "sYugaNFT: invalid tokenId_");
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId_;
        _yugaVault.withdrawNFT(address(_yugaNft), tokenIds);
        require(address(this) == _yugaNft.ownerOf(tokenId_), "sYugaNFT: invalid tokenId_");
        _yugaNft.safeTransferFrom(address(this), _msgSender(), tokenId_);

        // clear minter
        delete minterOf[tokenId_];

        _removeTokenFromStakerEnumeration(stakerOf(tokenId_), tokenId_);

        _burn(tokenId_);
    }

    function burn(uint256[] calldata tokenIds_) external override {
        uint256 tokenId_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            require(_msgSender() == ownerOf(tokenId_), "sYugaNFT: only owner can burn");
            require(address(_yugaVault) == _yugaNft.ownerOf(tokenId_), "sYugaNFT: invalid tokenId_");
        }

        _yugaVault.withdrawNFT(address(_yugaNft), tokenIds_);

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            require(address(this) == _yugaNft.ownerOf(tokenId_), "sYugaNFT: invalid tokenId_");
            _yugaNft.safeTransferFrom(address(this), _msgSender(), tokenId_);
            // clear minter
            delete minterOf[tokenId_];
            _removeTokenFromStakerEnumeration(stakerOf(tokenId_), tokenId_);
            _burn(tokenId_);
        }
    }

    function stakerOf(uint256 tokenId_) public view override returns (address) {
        return _yugaVault.stakerOf(address(_yugaNft), tokenId_);
    }

    function _addTokenToStakerEnumeration(address staker_, uint256 tokenId_) private {
        uint256 length = totalStaked[staker_];
        _stakedTokens[staker_][length] = tokenId_;
        _stakedTokensIndex[tokenId_] = length;
        totalStaked[staker_] += 1;
    }

    function _removeTokenFromStakerEnumeration(address staker_, uint256 tokenId_) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = totalStaked[staker_] - 1;
        uint256 tokenIndex = _stakedTokensIndex[tokenId_];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _stakedTokens[staker_][lastTokenIndex];

            _stakedTokens[staker_][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _stakedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _stakedTokensIndex[tokenId_];
        delete _stakedTokens[staker_][lastTokenIndex];
        totalStaked[stakerOf(tokenId_)] -= 1;
    }

    function tokenOfStakerByIndex(address staker_, uint256 index) external view override returns (uint256) {
        require(index < totalStaked[staker_], "sYugaNFT: staker index out of bounds");
        return _stakedTokens[staker_][index];
    }

    function underlyingAsset() external view override returns (address) {
        return address(_yugaNft);
    }

    function tokenURI(uint256 tokenId_) public view override(ERC721, IERC721Metadata) returns (string memory) {
        return _yugaNft.tokenURI(tokenId_);
    }
}
