// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import {IERC721MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721MetadataUpgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol";
import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721EnumerableUpgradeable.sol";

interface IStakedNft is IERC721MetadataUpgradeable, IERC721ReceiverUpgradeable, IERC721EnumerableUpgradeable {
    function mint(address to, uint256[] calldata tokenIds) external;

    function mintToReceiver(address to_, uint256[] calldata tokenIds_) external;

    function burn(uint256[] calldata tokenIds) external;

    function burnToReceiver(uint256[] calldata tokenIds_, address receiverOfUnderlying) external;

    /**
     * @dev Returns the staker of the `tokenId` token.
     */
    function stakerOf(uint256 tokenId) external view returns (address);

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
