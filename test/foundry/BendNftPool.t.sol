pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendNftPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function test_deposit_basic() public {
        super.prepareAllApprovals(testUser0);
        super.prepareMintNfts(testUser0, 5);

        vm.startPrank(testUser0);

        nftPool.deposit(address(mockBAYC), testBaycTokenIds);
        nftPool.withdraw(address(mockBAYC), testBaycTokenIds);

        nftPool.deposit(address(mockMAYC), testMaycTokenIds);
        nftPool.withdraw(address(mockMAYC), testMaycTokenIds);

        nftPool.deposit(address(mockBAKC), testBakcTokenIds);
        nftPool.withdraw(address(mockBAKC), testBakcTokenIds);

        vm.stopPrank();
    }
}
