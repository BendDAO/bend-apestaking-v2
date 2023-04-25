pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendCoinPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function test_deposit() public {
        address user = testUsers[0];
        vm.startPrank(user);

        uint256 depositAmount = 1000000 * 10**18;
        mockApeCoin.mint(depositAmount);
        mockApeCoin.approve(address(coinPool), depositAmount);

        // deposit some coins
        coinPool.deposit(depositAmount, user);

        uint256 userShareAfterDeposit = coinPool.balanceOf(user);
        assertEq(userShareAfterDeposit, depositAmount, "user share not match");

        vm.stopPrank();

        // do some stake
        vm.startPrank(botAdmin);

        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.coinStakeThreshold = 0;
        stakeManager.compound(compoundArgs1);

        mockApeStaking.pools(0);

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        mockApeStaking.pools(0);

        IStakeManager.CompoundArgs memory compoundArgs2;
        compoundArgs2.claimCoinPool = true;
        stakeManager.compound(compoundArgs2);

        vm.stopPrank();

        // withdraw all coins
        vm.startPrank(user);

        uint256 withdrawAmount = coinPool.assetBalanceOf(user);
        assertGt(withdrawAmount, depositAmount, "withdraw should greater than deposit");
        coinPool.withdraw(withdrawAmount, user, user);

        uint256 userShareAfterWithdraw = coinPool.balanceOf(user);
        assertEq(userShareAfterWithdraw, 0, "user share not match");

        vm.stopPrank();
    }

    function test_RevertWhen_BalanceNotEnough() public {
        address user = testUsers[0];
        vm.startPrank(user);

        vm.expectRevert("ERC20: insufficient allowance");
        coinPool.deposit(1000 * 10**18, user);

        vm.stopPrank();
    }
}
