// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC721EnumerableUpgradeable, ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {IERC721MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol";

import {IStakedNft} from "../interfaces/IStakedNft.sol";
import {INftVault} from "../interfaces/INftVault.sol";

abstract contract StNft is IStakedNft, OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC721EnumerableUpgradeable {
    IERC721MetadataUpgradeable private _nft;
    INftVault public nftVault;

    // Mapping from staker to list of staked token IDs
    mapping(address => mapping(uint256 => uint256)) private _stakedTokens;

    // Mapping from token ID to index of the staker tokens list
    mapping(uint256 => uint256) private _stakedTokensIndex;

    // Mapping from staker to total staked amount of tokens
    mapping(address => uint256) public totalStaked;

    string private _customBaseURI;

    function __StNft_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __StNft_init(
        IERC721MetadataUpgradeable nft_,
        INftVault nftVault_,
        string memory name_,
        string memory symbol_
    ) internal onlyInitializing {
        __Ownable_init();
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();

        _nft = nft_;
        nftVault = nftVault_;
        _nft.setApprovalForAll(address(nftVault), true);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165Upgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return interfaceId == type(IStakedNft).interfaceId || super.supportsInterface(interfaceId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view override returns (bytes4) {
        require(_msgSender() == address(_nft), "StNft: nft not acceptable");
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function mint(address to_, uint256[] calldata tokenIds_) external override nonReentrant {
        address staker_ = _msgSender();
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            _nft.safeTransferFrom(_msgSender(), address(this), tokenIds_[i]);
        }
        nftVault.depositNft(address(_nft), tokenIds_, staker_);
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            _addTokenToStakerEnumeration(staker_, tokenIds_[i]);
            _safeMint(to_, tokenIds_[i]);
        }
        emit Minted(to_, tokenIds_);
    }

    function burn(uint256[] calldata tokenIds_) external override nonReentrant {
        uint256 tokenId_;
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            require(_msgSender() == ownerOf(tokenId_), "stNft: only owner can burn");
            require(address(nftVault) == _nft.ownerOf(tokenId_), "stNft: invalid tokenId_");

            _removeTokenFromStakerEnumeration(stakerOf(tokenId_), tokenId_);
            _burn(tokenId_);
        }

        nftVault.withdrawNft(address(_nft), tokenIds_);

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            tokenId_ = tokenIds_[i];
            _nft.safeTransferFrom(address(this), _msgSender(), tokenIds_[i]);
        }
        emit Burned(_msgSender(), tokenIds_);
    }

    function stakerOf(uint256 tokenId_) public view override returns (address) {
        return nftVault.stakerOf(address(_nft), tokenId_);
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
        totalStaked[staker_] -= 1;
    }

    function tokenOfStakerByIndex(address staker_, uint256 index) external view override returns (uint256) {
        require(index < totalStaked[staker_], "stNft: staker index out of bounds");
        return _stakedTokens[staker_][index];
    }

    function underlyingAsset() external view override returns (address) {
        return address(_nft);
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        _customBaseURI = baseURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _customBaseURI;
    }

    function tokenURI(
        uint256 tokenId_
    ) public view override(ERC721Upgradeable, IERC721MetadataUpgradeable) returns (string memory) {
        if (bytes(_customBaseURI).length > 0) {
            return super.tokenURI(tokenId_);
        }

        return _nft.tokenURI(tokenId_);
    }

    function setDelegateCash(address delegate_, uint256[] calldata tokenIds_, bool value_) external override {
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            require(_msgSender() == ownerOf(tokenIds_[i]), "stNft: only owner can delegate");
        }
        nftVault.setDelegateCash(delegate_, address(_nft), tokenIds_, value_);
    }
}
