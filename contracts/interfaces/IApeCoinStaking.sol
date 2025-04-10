// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IApeCoinStaking {
    struct Pool {
        uint48 lastRewardedTimestampHour;
        uint16 lastRewardsRangeIndex;
        uint96 stakedAmount;
        uint96 accumulatedRewardsPerShare;
        TimeRange[] timeRanges;
    }

    struct TimeRange {
        uint48 startTimestampHour;
        uint48 endTimestampHour;
        uint96 rewardsPerHour;
        uint96 capPerPosition;
    }

    struct PoolWithoutTimeRange {
        uint48 lastRewardedTimestampHour;
        uint16 lastRewardsRangeIndex;
        uint96 stakedAmount;
        uint96 accumulatedRewardsPerShare;
    }

    struct PoolUI {
        uint256 poolId;
        uint256 stakedAmount;
        TimeRange currentTimeRange;
    }

    struct Position {
        uint256 stakedAmount;
        int256 rewardsDebt;
    }

    // public varaiables
    function pools(uint256 poolId_) external view returns (PoolWithoutTimeRange memory);

    function nftContracts(uint256 poolId_) external view returns (address);

    function nftPosition(uint256 poolId_, uint256 tokenId_) external view returns (Position memory);

    // public read methods
    function getTimeRangeBy(uint256 _poolId, uint256 _index) external view returns (TimeRange memory);

    function rewardsBy(uint256 _poolId, uint256 _from, uint256 _to) external view returns (uint256, uint256);

    function getPoolsUI() external view returns (PoolUI memory, PoolUI memory, PoolUI memory);

    function stakedTotal(
        uint256[] memory baycTokenIds,
        uint256[] memory maycTokenIds,
        uint256[] memory bakcTokenIds
    ) external view returns (uint256 total);

    function pendingRewards(uint256 _poolId, uint256 _tokenId) external view returns (uint256);

    function pendingClaims(
        bytes32 guid
    ) external view returns (uint8 poolId, uint8 requestType, address caller, address recipient, uint96 numNfts);

    // public write methods
    function deposit(uint256 poolId, uint256[] calldata tokenIds, uint256[] calldata amounts) external payable;

    function claim(uint256 poolId, uint256[] calldata tokenIds, address recipient) external payable;

    function withdraw(
        uint256 poolId,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        address recipient
    ) external payable;
}
