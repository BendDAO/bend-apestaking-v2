// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

contract MockAddressProviderV2 {
    MockPoolManager private _poolManager;
    MockPoolLensV2 private _poolLens;

    constructor() {
        _poolManager = new MockPoolManager();
        _poolLens = new MockPoolLensV2();
    }

    function getPoolManager() public view returns (address) {
        return address(_poolManager);
    }

    function getPoolModuleProxy(uint moduleId) public view returns (address) {
        if (moduleId == 4) {
            return address(_poolLens);
        }

        revert("Unkonwn moduleId");
    }
}

contract MockPoolManager {
    uint256 private _dummy;
}

contract MockPoolLensV2 {
    struct MockUserAssetData {
        uint256 totalCrossSupply;
        uint256 totalIsolateSupply;
        uint256 totalCrossBorrow;
        uint256 totalIsolateBorrow;
    }
    struct MockERC721TokenData {
        address owner;
        uint8 supplyMode;
        address lockerAddr;
    }

    mapping(address => mapping(uint32 => mapping(address => MockUserAssetData))) private _userAssetDatas;
    mapping(uint32 => mapping(address => mapping(uint256 => MockERC721TokenData))) private _erc721TokenDatas;

    function getUserAssetData(
        address user,
        uint32 poolId,
        address asset
    )
        public
        view
        returns (
            uint256 totalCrossSupply,
            uint256 totalIsolateSupply,
            uint256 totalCrossBorrow,
            uint256 totalIsolateBorrow
        )
    {
        MockUserAssetData memory uad = _userAssetDatas[user][poolId][asset];
        return (uad.totalCrossSupply, uad.totalIsolateSupply, uad.totalCrossBorrow, uad.totalIsolateBorrow);
    }

    function setUserAssetData(
        address user,
        uint32 poolId,
        address asset,
        uint256 totalCrossSupply,
        uint256 totalIsolateSupply,
        uint256 totalCrossBorrow,
        uint256 totalIsolateBorrow
    ) public {
        MockUserAssetData storage uad = _userAssetDatas[user][poolId][asset];
        uad.totalCrossSupply = totalCrossSupply;
        uad.totalIsolateSupply = totalIsolateSupply;
        uad.totalCrossBorrow = totalCrossBorrow;
        uad.totalIsolateBorrow = totalIsolateBorrow;
    }

    function getERC721TokenData(
        uint32 poolId,
        address asset,
        uint256 tokenId
    ) public view returns (address, uint8, address) {
        MockERC721TokenData memory etd = _erc721TokenDatas[poolId][asset][tokenId];
        return (etd.owner, etd.supplyMode, etd.lockerAddr);
    }

    function setERC721TokenData(
        uint32 poolId,
        address asset,
        uint256 tokenId,
        address owner,
        uint8 supplyMode,
        address lockerAddr
    ) public {
        MockERC721TokenData storage etd = _erc721TokenDatas[poolId][asset][tokenId];
        etd.owner = owner;
        etd.supplyMode = supplyMode;
        etd.lockerAddr = lockerAddr;
    }
}
