// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IPoolViewer {
    struct PoolState {
        uint256 coinPoolPendingApeCoin;
        uint256 coinPoolPendingRewards;
        uint256 coinPoolStakedAmount;
        uint256 baycPoolMaxCap;
        uint256 maycPoolMaxCap;
        uint256 bakcPoolMaxCap;
    }

    function viewPool() external view returns (PoolState memory);

    function viewNftPoolPendingRewards(address nft_, uint256[] calldata tokenIds_) external view returns (uint256);
}
