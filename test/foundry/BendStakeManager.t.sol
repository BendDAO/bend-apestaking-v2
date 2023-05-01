pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendStakeManagerTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function test_compound_StakeApeCoin() public {
        address testUser = testUsers[0];
        uint256 depositCoinAmount = 1_000_000 * 1e18;

        // deposit some coins
        vm.startPrank(testUser);
        mockApeCoin.mint(depositCoinAmount);
        mockApeCoin.approve(address(coinPool), depositCoinAmount);
        coinPool.deposit(depositCoinAmount, testUser);
        vm.stopPrank();

        // stake all coins
        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.coinStakeThreshold = 0;
        stakeManager.compound(compoundArgs1);
        vm.stopPrank();

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs2;
        compoundArgs2.claimCoinPool = true;
        stakeManager.compound(compoundArgs2);
        vm.stopPrank();

        uint256 userAssetAmount = coinPool.assetBalanceOf(testUser);

        // withdraw all coins
        vm.startPrank(testUser);
        coinPool.withdraw(userAssetAmount, testUser, testUser);
        vm.stopPrank();

        uint256 userBalanceAfterWithdraw = mockApeCoin.balanceOf(testUser);
        assertEq(userBalanceAfterWithdraw, userAssetAmount, "user balance not match after withdraw");
        assertGt(userAssetAmount, depositCoinAmount, "user asset not greater than deposited amout");
    }

    function test_compound_StakeBAYC() public {
        address testUser = testUsers[0];
        uint256 depositCoinAmount = 1_000_000 * 1e18;
        uint256[] memory testBaycTokenIds = new uint256[](1);

        // deposit some coins
        vm.startPrank(testUser);
        mockApeCoin.mint(depositCoinAmount);
        mockApeCoin.approve(address(coinPool), depositCoinAmount);
        coinPool.deposit(depositCoinAmount, testUser);
        vm.stopPrank();

        // deposit some nfts
        vm.startPrank(testUser);
        mockBAYC.setApprovalForAll(address(nftPool), true);
        stBAYC.setApprovalForAll(address(nftPool), true);

        testBaycTokenIds[0] = 100;
        mockBAYC.mint(testBaycTokenIds[0]);
        nftPool.deposit(address(mockBAYC), testBaycTokenIds);
        vm.stopPrank();

        // stake all nfts
        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.stake.bayc = testBaycTokenIds;
        stakeManager.compound(compoundArgs1);
        vm.stopPrank();

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs2;
        compoundArgs2.claim.bayc = testBaycTokenIds;
        stakeManager.compound(compoundArgs2);
        vm.stopPrank();

        vm.startPrank(testUser);
        uint256 rewardsAmount = nftPool.claimable(address(mockBAYC), testBaycTokenIds);
        assertGt(rewardsAmount, 0, "rewards should greater than 0");

        nftPool.withdraw(address(mockBAYC), testBaycTokenIds);
        uint256 balanceAmount = mockApeCoin.balanceOf(testUser);
        assertEq(balanceAmount, rewardsAmount, "balance not match rewards");
        vm.stopPrank();
    }
}
