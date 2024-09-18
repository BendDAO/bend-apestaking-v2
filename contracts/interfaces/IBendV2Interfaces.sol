// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

interface IAddressProviderV2 {
    function getPoolManager() external view returns (address);

    function getPoolModuleProxy(uint moduleId) external view returns (address);
}

interface IPoolLensV2 {
    function getUserAssetData(
        address user,
        uint32 poolId,
        address asset
    )
        external
        view
        returns (
            uint256 totalCrossSupply,
            uint256 totalIsolateSupply,
            uint256 totalCrossBorrow,
            uint256 totalIsolateBorrow
        );

    function getERC721TokenData(
        uint32 poolId,
        address asset,
        uint256 tokenId
    ) external view returns (address, uint8, address);
}
