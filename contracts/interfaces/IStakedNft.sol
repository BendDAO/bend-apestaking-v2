// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC721Metadata} from "@openzeppelin/contracts/interfaces/IERC721Metadata.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";

interface IStakedNft is IERC721Metadata, IERC721Receiver, IERC721Enumerable {
    function mint(address staker, address to, uint256[] calldata tokenIds) external;

    function burn(uint256[] calldata tokenIds) external;

    /**
     * @dev Returns the staker of the `tokenId` token.
     */
    function stakerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev Returns the minter of the `tokenId` token.
     */
    function minterOf(uint256 tokenId) external view returns (address);

    /**
     * @dev Returns a token ID owned by `staker` at a given `index` of its token list.
     * Use along with {totalStaked} to enumerate all of ``staker``'s tokens.
     */

    function tokenOfStakerByIndex(address staker, uint256 index) external view returns (uint256);

    /**
     * @dev Returns the total staked amount of tokens for staker.
     */
    function totalStaked(address staker) external view returns (uint256);

    function underlyingAsset() external view returns (address);

    function setDelegateCash(address delegate, uint256[] calldata tokenIds, bool value) external;
}
