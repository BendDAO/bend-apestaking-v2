pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendNftPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function testSingleUserDepositWithdrawBAYCNoRewards() public {
        super.prepareAllApprovals(testUser0);
        super.prepareMintNfts(testUser0, 1);

        vm.startPrank(testUser0);

        NftPoolData memory poolDataBeforeDeposit = getNftPoolDataInContracts(address(mockBAYC));
        NftTokenData memory tokenDataBeforeDeposit = getNftTokenDataInContracts(address(mockBAYC), testBaycTokenIds[0]);

        nftPool.deposit(address(mockBAYC), testBaycTokenIds);

        // check results
        NftPoolData memory poolDataAfterDeposit = getNftPoolDataInContracts(address(mockBAYC));
        NftTokenData memory tokenDataAfterDeposit = getNftTokenDataInContracts(address(mockBAYC), testBaycTokenIds[0]);

        NftPoolData memory poolDataExpectedAfterDeposit = calcExpectedNftPoolDataAfterDeposit(
            testVars.curUser,
            testBaycTokenIds[0],
            poolDataBeforeDeposit,
            tokenDataBeforeDeposit
        );
        NftTokenData memory tokenDataExpectedAfterDeposit = calcExpectedNftTokenDataAfterDeposit(
            testVars.curUser,
            testBaycTokenIds[0],
            poolDataBeforeDeposit,
            tokenDataBeforeDeposit
        );

        assertEq(
            poolDataAfterDeposit.totalNftAmount,
            poolDataExpectedAfterDeposit.totalNftAmount,
            "total amount not match"
        );
        assertEq(
            poolDataAfterDeposit.accumulatedRewardsPerNft,
            poolDataExpectedAfterDeposit.accumulatedRewardsPerNft,
            "pool rewards index not match"
        );
        assertEq(
            tokenDataAfterDeposit.rewardsDebt,
            tokenDataExpectedAfterDeposit.rewardsDebt,
            "token rewards debt not match"
        );
        assertEq(
            tokenDataAfterDeposit.claimableRewards,
            tokenDataExpectedAfterDeposit.claimableRewards,
            "token claimable rewards not match"
        );

        nftPool.withdraw(address(mockBAYC), testBaycTokenIds);

        vm.stopPrank();
    }

    function testSingleUserBatchDepositWithdrawNoRewards() public {
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
