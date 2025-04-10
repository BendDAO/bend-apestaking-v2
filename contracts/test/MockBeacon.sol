// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

contract MockBeacon {
    function quoteRead(
        address baseCollectionAddress,
        uint256[] calldata tokenIds,
        uint32[] calldata dstEids,
        uint128 supplementalGasLimit
    ) external pure returns (uint256 nativeFee, uint256 lzTokenFee) {
        baseCollectionAddress;
        tokenIds;
        dstEids;
        supplementalGasLimit;

        return (0, 0);
    }
}
