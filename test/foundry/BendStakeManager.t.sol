pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendStakeManagerTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function test_compound_StakeApeCoin() public {
        uint256 depositCoinAmount = 1_000_000 * 1e18;

        super.prepareAllApprovals(testUser0);
        super.prepareDepositCoins(testUser0, depositCoinAmount);

        vm.startPrank(botAdmin);

        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.coinStakeThreshold = 0;
        stakeManager.compound(compoundArgs1);

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        IStakeManager.CompoundArgs memory compoundArgs2;
        compoundArgs2.claimCoinPool = true;
        stakeManager.compound(compoundArgs2);

        vm.stopPrank();

        vm.startPrank(testUser0);
        uint256 assetAmount = coinPool.assetBalanceOf(testUser0);
        assertGt(assetAmount, depositCoinAmount, "asset should greater than deposit");
        vm.stopPrank();
    }

    function test_compound_StakeBAYC() public {
        uint256 depositCoinAmount = 1_000_000 * 1e18;

        super.prepareAllApprovals(testUser0);
        super.prepareDepositCoins(testUser0, depositCoinAmount);
        super.prepareDepositNfts(testUser0, 5);

        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.stake.bayc = testBaycTokenIds;
        stakeManager.compound(compoundArgs1);

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        IStakeManager.CompoundArgs memory compoundArgs2;
        compoundArgs2.claim.bayc = testBaycTokenIds;
        stakeManager.compound(compoundArgs2);

        vm.stopPrank();

        vm.startPrank(testUser0);
        uint256 rewardsAmount = nftPool.claimable(address(mockBAYC), testBaycTokenIds);
        assertGt(rewardsAmount, 0, "rewards should greater than 0");
        nftPool.withdraw(address(mockBAYC), testBaycTokenIds);
        uint256 balanceAmount = mockApeCoin.balanceOf(testUser0);
        assertEq(balanceAmount, rewardsAmount, "balance not match rewards");
        vm.stopPrank();
    }
}
