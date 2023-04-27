pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendStakeManagerTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function test_compound_StakeApeCoin() public {
        super.prepareAllApprovals(testUser0);
        super.prepareDepositCoins(testUser0, 1_000_000 * 1e18);

        vm.startPrank(botAdmin);

        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.coinStakeThreshold = 0;
        stakeManager.compound(compoundArgs1);

        vm.stopPrank();
    }

    function test_compound_StakeBAYC() public {
        super.prepareAllApprovals(testUser0);
        super.prepareDepositCoins(testUser0, 1_000_000 * 1e18);
        super.prepareDepositNfts(testUser0, 5);

        vm.startPrank(botAdmin);
        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.stake.bayc = testBaycTokenIds;
        stakeManager.compound(compoundArgs1);
        vm.stopPrank();
    }
}
