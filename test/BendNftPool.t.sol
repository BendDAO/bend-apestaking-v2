pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendNftPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function test_deposit() public {
        address user = users[0];
        vm.startPrank(user);

        uint256 tokenId = 100;
        mockBAYC.mint(tokenId);
        mockBAYC.approve(address(nftPool), tokenId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        nftPool.deposit(address(mockBAYC), tokenIds);
    }
}
