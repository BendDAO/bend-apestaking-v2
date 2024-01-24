// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.18;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IDelegateRegistryV2} from "../interfaces/IDelegateRegistryV2.sol";

contract MockDelegationRegistryV2 is IDelegateRegistryV2 {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @dev Only this mapping should be used to verify delegations; the other mapping arrays are for enumerations
    mapping(bytes32 => Delegation) internal allDelegations;

    /// @dev Vault delegation enumeration outbox, for pushing new hashes only
    mapping(address => EnumerableSet.Bytes32Set) internal outgoingDelegationHashes;

    /// @dev Delegate enumeration inbox, for pushing new hashes only
    mapping(address => EnumerableSet.Bytes32Set) internal incomingDelegationHashes;

    function delegateERC721(
        address to,
        address contract_,
        uint256 tokenId,
        bytes32 rights,
        bool enable
    ) public payable override returns (bytes32 delegationHash) {
        delegationHash = keccak256(abi.encodePacked(rights, msg.sender, to, contract_, tokenId));
        if (enable) {
            allDelegations[delegationHash] = Delegation(
                DelegationType.ERC721,
                to,
                msg.sender,
                rights,
                contract_,
                tokenId,
                0
            );

            outgoingDelegationHashes[msg.sender].add(delegationHash);
            incomingDelegationHashes[to].add(delegationHash);
        } else {
            delete allDelegations[delegationHash];

            outgoingDelegationHashes[msg.sender].remove(delegationHash);
            incomingDelegationHashes[to].remove(delegationHash);
        }
    }

    function getOutgoingDelegations(address from) external view override returns (Delegation[] memory delegations) {
        bytes32[] memory delegationHashes = outgoingDelegationHashes[from].values();
        return _getDelegationsFromHashes(delegationHashes);
    }

    function getDelegationsFromHashes(
        bytes32[] calldata delegationHashes
    ) public view override returns (Delegation[] memory delegations) {
        return _getDelegationsFromHashes(delegationHashes);
    }

    function _getDelegationsFromHashes(
        bytes32[] memory delegationHashes
    ) private view returns (Delegation[] memory delegations) {
        delegations = new Delegation[](delegationHashes.length);
        for (uint256 i = 0; i < delegationHashes.length; ++i) {
            delegations[i] = allDelegations[delegationHashes[i]];
        }
    }
}
