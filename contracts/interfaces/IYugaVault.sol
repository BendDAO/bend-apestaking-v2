// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;
import {IApeCoinStaking} from "./IApeCoinStaking.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IYugaVault is IERC721Receiver {
    function stakerOf(address nft_, uint256 tokenId_) external view returns (address);

    function ownerOf(address nft_, uint256 tokenId_) external view returns (address);

    function refundOf(address staker_, address nft_) external view returns (uint256 principal, uint256 reward);

    // deposit nft
    function depositNFT(
        address yugaNFT,
        uint256[] calldata tokenIds_,
        address staker
    ) external;

    // withdraw nft
    function withdrawNFT(address yugaNFT, uint256[] calldata tokenIds_) external;

    // staker withdraw ape coin
    function withdrawRefunds(address yugaNFT) external;

    // stake
    function stakeBaycPool(IApeCoinStaking.SingleNft[] calldata nfts_) external;

    function stakeMaycPool(IApeCoinStaking.SingleNft[] calldata nfts_) external;

    function stakeBakcPool(
        IApeCoinStaking.PairNftDepositWithAmount[] calldata baycPairs_,
        IApeCoinStaking.PairNftDepositWithAmount[] calldata maycPairs_
    ) external;

    // unstake
    function unstakeBaycPool(IApeCoinStaking.SingleNft[] calldata nfts_, address recipient_) external;

    function unstakeMaycPool(IApeCoinStaking.SingleNft[] calldata nfts_, address recipient_) external;

    function unstakeBakcPool(
        IApeCoinStaking.PairNftWithdrawWithAmount[] calldata baycPairs_,
        IApeCoinStaking.PairNftWithdrawWithAmount[] calldata maycPairs_,
        address recipient_
    ) external;

    // claim rewards
    function claimBaycPool(uint256[] calldata tokenIds_, address recipient_) external;

    function claimMaycPool(uint256[] calldata tokenIds_, address recipient_) external;

    function claimBakcPool(
        IApeCoinStaking.PairNft[] calldata baycPairs_,
        IApeCoinStaking.PairNft[] calldata maycPairs_,
        address recipient_
    ) external;
}
