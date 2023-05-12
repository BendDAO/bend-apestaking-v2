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
        address[] memory nfts = new address[](1);
        uint256[][] memory tokenIds = new uint256[][](1);

        nfts[0] = address(mockBAYC);
        tokenIds[0] = testBaycTokenIds;
        nftPool.deposit(nfts, tokenIds);

        nftPool.claim(nfts, tokenIds);

        nftPool.withdraw(nfts, tokenIds);

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

        address[] memory nfts = new address[](1);
        uint256[][] memory tokenIds = new uint256[][](1);

        nfts[0] = address(mockBAYC);
        tokenIds[0] = testBaycTokenIds;

        nftPool.deposit(nfts, tokenIds);

        nftPool.claim(nfts, tokenIds);

        nftPool.withdraw(nfts, tokenIds);

        vm.stopPrank();
    }

    function testBoundNFTClaimRewards() public {
        address testUser = testUsers[0];
        uint256[] memory testBaycTokenIds = new uint256[](1);

        vm.startPrank(testUser);

        mockBAYC.setApprovalForAll(address(nftPool), true);
        stBAYC.setApprovalForAll(address(nftPool), true);

        testBaycTokenIds[0] = 100;
        mockBAYC.mint(testBaycTokenIds[0]);

        address[] memory nfts = new address[](1);
        uint256[][] memory tokenIds = new uint256[][](1);

        nfts[0] = address(mockBAYC);
        tokenIds[0] = testBaycTokenIds;

        nftPool.deposit(nfts, tokenIds);

        stBAYC.setApprovalForAll(address(mockBnftStBAYC), true);
        mockBnftStBAYC.mint(testUser, testBaycTokenIds[0]);

        nftPool.claim(nfts, tokenIds);

        mockBnftStBAYC.burn(testBaycTokenIds[0]);

        nftPool.withdraw(nfts, tokenIds);

        vm.stopPrank();
    }
}
