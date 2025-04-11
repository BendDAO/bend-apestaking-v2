// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

contract MockBeacon {
    uint256 internal _nativeFee;
    uint256 internal _lzTokenFee;

    function setFees(uint256 nativeFee_, uint256 lzTokenFee_) public {
        _nativeFee = nativeFee_;
        _lzTokenFee = lzTokenFee_;
    }

    function quoteRead(
        address baseCollectionAddress,
        uint256[] calldata tokenIds,
        uint32[] calldata dstEids,
        uint128 supplementalGasLimit
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        baseCollectionAddress;
        tokenIds;
        dstEids;
        supplementalGasLimit;

        return (_nativeFee, _lzTokenFee);
    }
}
