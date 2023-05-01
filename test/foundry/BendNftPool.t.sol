pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendNftPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function testSingleUserDepositWithdrawBAYCNoRewards() public {
        address testUser = testUsers[0];
        uint256[] memory testBaycTokenIds = new uint256[](1);

        vm.startPrank(testUser);

        mockBAYC.setApprovalForAll(address(nftPool), true);
        stBAYC.setApprovalForAll(address(nftPool), true);

        testBaycTokenIds[0] = 100;
        mockBAYC.mint(testBaycTokenIds[0]);

        nftPool.deposit(address(mockBAYC), testBaycTokenIds);

        nftPool.withdraw(address(mockBAYC), testBaycTokenIds);

        vm.stopPrank();
    }

    function testSingleUserBatchDepositWithdrawBAYCNoRewards() public {
        address testUser = testUsers[0];
        uint256[] memory testBaycTokenIds = new uint256[](3);

        vm.startPrank(testUser);

        mockBAYC.setApprovalForAll(address(nftPool), true);
        stBAYC.setApprovalForAll(address(nftPool), true);

        testBaycTokenIds[0] = 100;
        mockBAYC.mint(testBaycTokenIds[0]);

        testBaycTokenIds[1] = 200;
        mockBAYC.mint(testBaycTokenIds[1]);

        testBaycTokenIds[2] = 300;
        mockBAYC.mint(testBaycTokenIds[2]);

        nftPool.deposit(address(mockBAYC), testBaycTokenIds);

        nftPool.withdraw(address(mockBAYC), testBaycTokenIds);

        vm.stopPrank();
    }
}
