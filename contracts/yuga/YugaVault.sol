// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IYugaVault, IApeCoinStaking, IERC721Receiver} from "../interfaces/IYugaVault.sol";

contract YugaVault is IYugaVault, Ownable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for uint248;

    uint256 private constant BAYC_POOL_ID = 1;
    uint256 private constant MAYC_POOL_ID = 2;
    uint256 private constant BAKC_POOL_ID = 3;

    struct NftStatus {
        address owner;
        address staker;
    }

    struct Refund {
        uint256 principal;
        uint256 reward;
    }
    // nft address =>  nft tokenId => nftStatus
    mapping(address => mapping(uint256 => NftStatus)) private _nfts;
    // nft address => staker address => refund
    mapping(address => mapping(address => Refund)) private _refunds;

    IApeCoinStaking public apeCoinStaking;

    constructor(IApeCoinStaking apeCoinStaking_) {
        apeCoinStaking = apeCoinStaking_;
    }

    function _bayc() internal view returns (IERC721) {
        return IERC721(apeCoinStaking.nftContracts(BAYC_POOL_ID));
    }

    function _mayc() internal view returns (IERC721) {
        return IERC721(apeCoinStaking.nftContracts(MAYC_POOL_ID));
    }

    function _bakc() internal view returns (IERC721) {
        return IERC721(apeCoinStaking.nftContracts(BAKC_POOL_ID));
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        require(_isYugaNFT(_msgSender()), "YugaVault: nft not acceptable");
        return IERC721Receiver.onERC721Received.selector;
    }

    function _isYugaNFT(address nft_) internal view returns (bool) {
        if (nft_ == address(_bayc())) {
            return true;
        }
        if (nft_ == address(_mayc())) {
            return true;
        }
        if (nft_ == address(_bakc())) {
            return true;
        }

        return false;
    }

    function stakerOf(address nft_, uint256 tokenId_) external view returns (address) {
        return _stakerOf(nft_, tokenId_);
    }

    function ownerOf(address nft_, uint256 tokenId_) external view returns (address) {
        return _ownerOf(nft_, tokenId_);
    }

    function _stakerOf(address nft_, uint256 tokenId_) internal view returns (address) {
        return _nfts[nft_][tokenId_].staker;
    }

    function _ownerOf(address nft_, uint256 tokenId_) internal view returns (address) {
        return _nfts[nft_][tokenId_].owner;
    }

    function refundOf(address staker_, address nft_) external view returns (uint256 principal, uint256 reward) {
        Refund memory refund_ = _refunds[nft_][staker_];
        return (refund_.principal, refund_.reward);
    }

    function _apeCoin() internal view returns (IERC20) {
        return IERC20(apeCoinStaking.apeCoin());
    }

    function depositNFT(
        address yugaNFT,
        uint256[] calldata tokenIds_,
        address staker
    ) external override {
        require(_isYugaNFT(yugaNFT), "YugaVault: not yuga nft");

        // transfer nft and set permission
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            IERC721(yugaNFT).safeTransferFrom(_msgSender(), address(this), tokenIds_[i]);
            _nfts[yugaNFT][tokenIds_[i]] = NftStatus(_msgSender(), staker);
        }
    }

    struct RefundSinglePoolVars {
        uint256 totalPrincipal;
        uint256 totalReward;
        uint256 totalPairingPrincipal;
        uint256 totalPairingReward;
        address staker;
        uint256 poolId;
        uint256 singleNftIndex;
        uint256 singleNftSize;
        uint256 pairingNftIndex;
        uint256 pairingNftSize;
    }

    function _refundSinglePool(address yugaNFT, uint256[] calldata tokenIds_) internal {
        require(address(_bayc()) == yugaNFT || address(_mayc()) == yugaNFT, "YugaVault: not bayc or mayc");
        require(tokenIds_.length > 0, "YugaVault: invalid tokenIds");
        RefundSinglePoolVars memory vars;

        vars.staker = _stakerOf(yugaNFT, tokenIds_[0]);

        uint256 apeCoinBalance = _apeCoin().balanceOf(address(this));

        IApeCoinStaking.SingleNft[] memory singleNftsContainer_ = new IApeCoinStaking.SingleNft[](tokenIds_.length);

        IApeCoinStaking.PairNftWithdrawWithAmount[]
            memory pairingNftsContainer_ = new IApeCoinStaking.PairNftWithdrawWithAmount[](tokenIds_.length);

        vars.poolId = BAYC_POOL_ID;
        if (address(_mayc()) == yugaNFT) {
            vars.poolId = MAYC_POOL_ID;
        }

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            uint256 tokenId_ = tokenIds_[i];
            require(_msgSender() == _ownerOf(yugaNFT, tokenId_), "YugaVault: caller must be nft owner");
            require(vars.staker == _stakerOf(yugaNFT, tokenId_), "YugaVault: staker must be same");
            uint256 stakedAmount = apeCoinStaking.nftPosition(vars.poolId, tokenId_).stakedAmount;

            // Still have ape coin staking in single pool
            if (stakedAmount > 0) {
                vars.totalPrincipal += stakedAmount;
                singleNftsContainer_[vars.singleNftIndex] = IApeCoinStaking.SingleNft({
                    tokenId: tokenId_.toUint32(),
                    amount: stakedAmount.toUint224()
                });
                vars.singleNftIndex += 1;
                vars.singleNftSize += 1;
            }

            IApeCoinStaking.PairingStatus memory pairingStatus = apeCoinStaking.mainToBakc(vars.poolId, tokenId_);
            uint256 bakcTokenId = pairingStatus.tokenId;
            stakedAmount = apeCoinStaking.nftPosition(BAKC_POOL_ID, bakcTokenId).stakedAmount;

            //  Still have ape coin staking in pairing pool
            if (pairingStatus.isPaired && stakedAmount > 0) {
                vars.totalPairingPrincipal += stakedAmount;
                pairingNftsContainer_[vars.pairingNftIndex] = IApeCoinStaking.PairNftWithdrawWithAmount({
                    mainTokenId: tokenId_.toUint32(),
                    bakcTokenId: bakcTokenId.toUint32(),
                    amount: stakedAmount.toUint184(),
                    isUncommit: true
                });
                vars.pairingNftIndex += 1;
                vars.pairingNftSize += 1;
            }
        }

        if (vars.singleNftSize > 0) {
            IApeCoinStaking.SingleNft[] memory singleNfts_ = new IApeCoinStaking.SingleNft[](vars.singleNftSize);
            for (uint256 i = 0; i < vars.singleNftSize; i++) {
                singleNfts_[i] = singleNftsContainer_[i];
            }
            if (address(_bayc()) == yugaNFT) {
                apeCoinStaking.withdrawBAYC(singleNfts_, address(this));
            } else {
                apeCoinStaking.withdrawMAYC(singleNfts_, address(this));
            }
            vars.totalReward = _apeCoin().balanceOf(address(this)) - apeCoinBalance - vars.totalPrincipal;
            // refund ape coin for single nft
            if (vars.staker != address(0)) {
                Refund storage _refund = _refunds[yugaNFT][vars.staker];
                _refund.principal += vars.totalPrincipal;
                _refund.reward += vars.totalReward;
            }
        }

        if (vars.pairingNftSize > 0) {
            IApeCoinStaking.PairNftWithdrawWithAmount[]
                memory pairingNfts_ = new IApeCoinStaking.PairNftWithdrawWithAmount[](vars.pairingNftSize);
            for (uint256 i = 0; i < vars.pairingNftSize; i++) {
                pairingNfts_[i] = pairingNftsContainer_[i];
            }
            apeCoinBalance = _apeCoin().balanceOf(address(this));
            IApeCoinStaking.PairNftWithdrawWithAmount[] memory emptyNfts;

            if (address(_bayc()) == yugaNFT) {
                apeCoinStaking.withdrawBAKC(pairingNfts_, emptyNfts);
            } else {
                apeCoinStaking.withdrawBAKC(emptyNfts, pairingNfts_);
            }
            vars.totalPairingReward = _apeCoin().balanceOf(address(this)) - apeCoinBalance - vars.totalPairingPrincipal;

            // refund ape coin for paring nft
            Refund storage _refund = _refunds[address(_bakc())][vars.staker];
            _refund.principal += vars.totalPairingPrincipal;
            _refund.reward += vars.totalPairingReward;
        }
    }

    struct RefundPairingPoolVars {
        uint256 totalPrincipal;
        uint256 totalReward;
        address staker;
        uint256 baycIndex;
        uint256 baycSize;
        uint256 maycIndex;
        uint256 maycSize;
    }

    function _refundPairingPool(uint256[] calldata tokenIds_) internal {
        require(tokenIds_.length > 0, "YugaVault: invalid tokenIds");
        RefundPairingPoolVars memory vars;

        vars.staker = _stakerOf(address(_bakc()), tokenIds_[0]);
        uint256 apeCoinBalance = _apeCoin().balanceOf(address(this));

        IApeCoinStaking.PairNftWithdrawWithAmount[]
            memory baycNftsContainer_ = new IApeCoinStaking.PairNftWithdrawWithAmount[](tokenIds_.length);

        IApeCoinStaking.PairNftWithdrawWithAmount[]
            memory maycNftsContainer_ = new IApeCoinStaking.PairNftWithdrawWithAmount[](tokenIds_.length);

        for (uint256 i = 0; i < tokenIds_.length; i++) {
            uint256 tokenId_ = tokenIds_[i];
            require(_msgSender() == _ownerOf(address(_bakc()), tokenId_), "YugaVault: caller must be nft owner");
            require(vars.staker == _stakerOf(address(_bakc()), tokenId_), "YugaVault: staker must be same");

            uint256 stakedAmount = apeCoinStaking.nftPosition(BAKC_POOL_ID, tokenId_).stakedAmount;
            if (stakedAmount > 0) {
                vars.totalPrincipal += stakedAmount;
                IApeCoinStaking.PairingStatus memory pBaycStatus = apeCoinStaking.bakcToMain(tokenId_, BAYC_POOL_ID);
                IApeCoinStaking.PairingStatus memory pMaycStatus = apeCoinStaking.bakcToMain(tokenId_, MAYC_POOL_ID);

                if (pBaycStatus.isPaired) {
                    baycNftsContainer_[vars.baycIndex] = IApeCoinStaking.PairNftWithdrawWithAmount({
                        mainTokenId: pBaycStatus.tokenId.toUint32(),
                        bakcTokenId: tokenId_.toUint32(),
                        amount: stakedAmount.toUint184(),
                        isUncommit: true
                    });
                    vars.baycIndex += 1;
                    vars.baycSize += 1;
                } else if (pMaycStatus.isPaired) {
                    maycNftsContainer_[vars.maycIndex] = IApeCoinStaking.PairNftWithdrawWithAmount({
                        mainTokenId: pMaycStatus.tokenId.toUint32(),
                        bakcTokenId: tokenId_.toUint32(),
                        amount: stakedAmount.toUint184(),
                        isUncommit: true
                    });
                    vars.maycIndex += 1;
                    vars.maycSize += 1;
                }
            }
        }

        if (vars.baycSize > 0 || vars.maycSize > 0) {
            IApeCoinStaking.PairNftWithdrawWithAmount[]
                memory baycNfts_ = new IApeCoinStaking.PairNftWithdrawWithAmount[](vars.baycSize);
            IApeCoinStaking.PairNftWithdrawWithAmount[]
                memory maycNfts_ = new IApeCoinStaking.PairNftWithdrawWithAmount[](vars.maycSize);
            for (uint256 i = 0; i < vars.baycSize; i++) {
                baycNfts_[i] = baycNftsContainer_[i];
            }
            for (uint256 i = 0; i < vars.maycSize; i++) {
                maycNfts_[i] = maycNftsContainer_[i];
            }
            apeCoinStaking.withdrawBAKC(baycNfts_, maycNfts_);
            vars.totalReward = _apeCoin().balanceOf(address(this)) - apeCoinBalance - vars.totalPrincipal;
            // refund ape coin for bakc
            if (vars.staker != address(0)) {
                Refund storage _refund = _refunds[address(_bakc())][vars.staker];
                _refund.principal += vars.totalPrincipal;
                _refund.reward += vars.totalReward;
            }
        }
    }

    function withdrawNFT(address yugaNFT, uint256[] calldata tokenIds_) external override {
        _refundApeCoin(yugaNFT, tokenIds_);
        // transfer nft to sender
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            // transfer nft
            IERC721(yugaNFT).safeTransferFrom(address(this), _msgSender(), tokenIds_[i]);
            delete _nfts[yugaNFT][tokenIds_[i]];
        }
    }

    function _refundApeCoin(address yugaNFT, uint256[] calldata tokenIds_) internal {
        require(_isYugaNFT(yugaNFT), "YugaVault: not yuga nft");
        require(tokenIds_.length > 0, "YugaVault: invalid tokenIds");
        if (address(_bayc()) == yugaNFT || address(_mayc()) == yugaNFT) {
            _refundSinglePool(yugaNFT, tokenIds_);
        } else if (address(_bakc()) == yugaNFT) {
            _refundPairingPool(tokenIds_);
        }
    }

    function withdrawRefunds(address yugaNFT) external override {
        Refund memory _refund = _refunds[yugaNFT][_msgSender()];
        uint256 amount = _refund.principal + _refund.reward;
        delete _refunds[yugaNFT][_msgSender()];
        _apeCoin().safeTransfer(_msgSender(), amount);
    }

    function stakeBaycPool(IApeCoinStaking.SingleNft[] calldata nfts_) external override {
        uint256 totalApeCoinAmount = 0;
        for (uint256 i = 0; i < nfts_.length; i++) {
            totalApeCoinAmount += nfts_[i].amount;
            require(
                _msgSender() == _stakerOf(address(_bayc()), nfts_[i].tokenId),
                "YugaVault: caller must be bayc staker"
            );
        }
        _apeCoin().safeTransferFrom(_msgSender(), address(this), totalApeCoinAmount);
        apeCoinStaking.depositBAYC(nfts_);
    }

    function stakeMaycPool(IApeCoinStaking.SingleNft[] calldata nfts_) external override {
        uint256 totalApeCoinAmount = 0;
        for (uint256 i = 0; i < nfts_.length; i++) {
            totalApeCoinAmount += nfts_[i].amount;
            require(
                _msgSender() == _stakerOf(address(_mayc()), nfts_[i].tokenId),
                "YugaVault: caller must be mayc staker"
            );
        }
        _apeCoin().safeTransferFrom(_msgSender(), address(this), totalApeCoinAmount);
        apeCoinStaking.depositMAYC(nfts_);
    }

    function stakeBakcPool(
        IApeCoinStaking.PairNftDepositWithAmount[] calldata baycPairs_,
        IApeCoinStaking.PairNftDepositWithAmount[] calldata maycPairs_
    ) external override {
        uint256 totalApeCoinAmount = 0;
        for (uint256 i = 0; i < baycPairs_.length; i++) {
            totalApeCoinAmount += baycPairs_[i].amount;
            require(
                _msgSender() == _stakerOf(address(_bayc()), baycPairs_[i].mainTokenId) &&
                    _msgSender() == _stakerOf(address(_bakc()), baycPairs_[i].bakcTokenId),
                "YugaVault: caller must be nft staker"
            );
        }

        for (uint256 i = 0; i < maycPairs_.length; i++) {
            totalApeCoinAmount += maycPairs_[i].amount;
            require(
                _msgSender() == _stakerOf(address(_mayc()), maycPairs_[i].mainTokenId) &&
                    _msgSender() == _stakerOf(address(_bakc()), maycPairs_[i].bakcTokenId),
                "YugaVault: caller must be nft staker"
            );
        }
        _apeCoin().safeTransferFrom(_msgSender(), address(this), totalApeCoinAmount);
        apeCoinStaking.depositBAKC(baycPairs_, maycPairs_);
    }

    function unstakeBaycPool(IApeCoinStaking.SingleNft[] calldata nfts_, address recipient_) external override {
        for (uint256 i = 0; i < nfts_.length; i++) {
            require(
                _msgSender() == _stakerOf(address(_bayc()), nfts_[i].tokenId),
                "YugaVault: caller must be nft staker"
            );
        }
        apeCoinStaking.withdrawBAYC(nfts_, recipient_);
    }

    function unstakeMaycPool(IApeCoinStaking.SingleNft[] calldata nfts_, address recipient_) external override {
        for (uint256 i = 0; i < nfts_.length; i++) {
            require(
                _msgSender() == _stakerOf(address(_mayc()), nfts_[i].tokenId),
                "YugaVault: caller must be nft staker"
            );
        }
        apeCoinStaking.withdrawMAYC(nfts_, recipient_);
    }

    function unstakeBakcPool(
        IApeCoinStaking.PairNftWithdrawWithAmount[] calldata baycPairs_,
        IApeCoinStaking.PairNftWithdrawWithAmount[] calldata maycPairs_,
        address recipient_
    ) external override {
        for (uint256 i = 0; i < baycPairs_.length; i++) {
            require(
                _msgSender() == _stakerOf(address(_bayc()), baycPairs_[i].mainTokenId) &&
                    _msgSender() == _stakerOf(address(_bakc()), baycPairs_[i].bakcTokenId),
                "YugaVault: caller must be nft staker"
            );
        }

        for (uint256 i = 0; i < maycPairs_.length; i++) {
            require(
                _msgSender() == _stakerOf(address(_mayc()), maycPairs_[i].mainTokenId) &&
                    _msgSender() == _stakerOf(address(_bakc()), maycPairs_[i].bakcTokenId),
                "YugaVault: caller must be nft staker"
            );
        }
        uint256 apeCoinAmount = _apeCoin().balanceOf(address(this));
        apeCoinStaking.withdrawBAKC(baycPairs_, maycPairs_);
        apeCoinAmount = _apeCoin().balanceOf(address(this)) - apeCoinAmount;
        _apeCoin().safeTransfer(recipient_, apeCoinAmount);
    }

    function claimBaycPool(uint256[] calldata tokenIds_, address recipient_) external override {
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            require(_msgSender() == _stakerOf(address(_bayc()), tokenIds_[i]), "YugaVault: caller must be nft staker");
        }
        apeCoinStaking.claimBAYC(tokenIds_, recipient_);
    }

    function claimMaycPool(uint256[] calldata tokenIds_, address recipient_) external override {
        for (uint256 i = 0; i < tokenIds_.length; i++) {
            require(_msgSender() == _stakerOf(address(_mayc()), tokenIds_[i]), "YugaVault: caller must be nft staker");
        }
        apeCoinStaking.claimMAYC(tokenIds_, recipient_);
    }

    function claimBakcPool(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_,
        address recipient_
    ) external override {
        for (uint256 i = 0; i < baycPairs_.length; i++) {
            require(
                _msgSender() == _stakerOf(address(_bayc()), baycPairs_[i].mainTokenId) &&
                    _msgSender() == _stakerOf(address(_bakc()), baycPairs_[i].bakcTokenId),
                "YugaVault: caller must be nft staker"
            );
        }

        for (uint256 i = 0; i < maycPairs_.length; i++) {
            require(
                _msgSender() == _stakerOf(address(_mayc()), maycPairs_[i].mainTokenId) &&
                    _msgSender() == _stakerOf(address(_bakc()), maycPairs_[i].bakcTokenId),
                "YugaVault: caller must be nft staker"
            );
        }
        apeCoinStaking.claimBAKC(baycPairs_, maycPairs_, recipient_);
    }
}
