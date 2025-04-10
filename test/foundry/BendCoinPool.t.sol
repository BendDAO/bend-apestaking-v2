pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendCoinPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function testSingleUserDepositWithdrawNoRewards() public {
        address testUser = testUsers[0];
        uint256 depositAmount = 1000000 * 10 ** 18;

        vm.startPrank(testUser);

        mockWAPE.deposit{value: depositAmount}();
        mockWAPE.approve(address(coinPool), depositAmount);

        uint256 poolBalanceBeforeDeposit = mockWAPE.balanceOf(address(coinPool));

        // deposit some coins
        coinPool.deposit(depositAmount, testUser);

        // withdraw all coins
        coinPool.withdraw(depositAmount, testUser, testUser);

        // check results
        uint256 userBalanceAfterWithdraw = mockWAPE.balanceOf(testUser);
        assertEq(userBalanceAfterWithdraw, depositAmount, "user balance not match after withdraw");

        uint256 poolBalanceAfterWithdraw = mockWAPE.balanceOf(address(coinPool));
        assertEq(poolBalanceAfterWithdraw, poolBalanceBeforeDeposit, "pool balance not match after withdraw");

        vm.stopPrank();
    }

    function testSingleUserDepositWithdrawHasRewards() public {
        address testUser = testUsers[0];
        uint256 depositAmount = 100000 * 10 ** 18;
        uint256 rewardsAmount = 200000 * 10 ** 18;

        uint256 poolBalanceBeforeDeposit = mockWAPE.balanceOf(address(coinPool));

        // deposit some coins
        vm.startPrank(testUser);
        mockWAPE.deposit{value: depositAmount}();
        mockWAPE.approve(address(coinPool), depositAmount);
        coinPool.deposit(depositAmount, testUser);
        vm.stopPrank();

        // make some rewards
        vm.deal(address(stakeManager), rewardsAmount);
        vm.startPrank(address(stakeManager));
        mockWAPE.deposit{value: rewardsAmount}();
        mockWAPE.approve(address(coinPool), rewardsAmount);
        coinPool.receiveApeCoin(0, rewardsAmount);
        vm.stopPrank();

        uint256 expectedUserBalanceAfterWithdraw = coinPool.assetBalanceOf(testUser);

        // withdraw all coins
        vm.startPrank(testUser);
        coinPool.withdraw(expectedUserBalanceAfterWithdraw, testUser, testUser);
        vm.stopPrank();

        // check results
        uint256 userBalanceAfterWithdraw = mockWAPE.balanceOf(testUser);
        assertEq(userBalanceAfterWithdraw, expectedUserBalanceAfterWithdraw, "user balance not match after withdraw");

        uint256 poolBalanceAfterWithdraw = mockWAPE.balanceOf(address(coinPool));
        assertGt(poolBalanceAfterWithdraw, poolBalanceBeforeDeposit, "pool balance not match after withdraw");
    }

    function testMutipleUserDepositWithdrawNoRewards() public {
        uint256 userIndex = 0;
        uint256 userCount = 3;
        uint256[] memory depositAmounts = new uint256[](userCount);

        for (userIndex = 0; userIndex < userCount; userIndex++) {
            vm.startPrank(testUsers[userIndex]);

            depositAmounts[userIndex] = 1000000 * 10 ** 18 * (userIndex + 1);
            mockWAPE.deposit{value: depositAmounts[userIndex]}();
            mockWAPE.approve(address(coinPool), depositAmounts[userIndex]);

            coinPool.deposit(depositAmounts[userIndex], testUsers[userIndex]);

            vm.stopPrank();
        }

        // withdraw all coins
        for (userIndex = 0; userIndex < userCount; userIndex++) {
            vm.startPrank(testUsers[userIndex]);

            coinPool.withdraw(depositAmounts[userIndex], testUsers[userIndex], testUsers[userIndex]);

            vm.stopPrank();
        }

        // check results
        for (userIndex = 0; userIndex < userCount; userIndex++) {
            uint256 userBalanceAfterWithdraw = mockWAPE.balanceOf(testUsers[userIndex]);
            assertEq(userBalanceAfterWithdraw, depositAmounts[userIndex], "user balance not match after withdraw");
        }
    }

    function testMutipleUserDepositWithdrawHasRewards() public {
        uint256 userIndex = 0;
        uint256 userCount = 3;
        uint256 totalDepositAmount = 0;
        uint256[] memory depositAmounts = new uint256[](userCount);
        uint256 totalRewardsAmount = 100000 * 10 ** 18 * userCount;

        for (userIndex = 0; userIndex < userCount; userIndex++) {
            vm.startPrank(testUsers[userIndex]);

            depositAmounts[userIndex] = 1000000 * 10 ** 18 * (userIndex + 1);
            totalDepositAmount += depositAmounts[userIndex];

            mockWAPE.deposit{value: depositAmounts[userIndex]}();
            mockWAPE.approve(address(coinPool), depositAmounts[userIndex]);

            coinPool.deposit(depositAmounts[userIndex], testUsers[userIndex]);

            vm.stopPrank();
        }

        // make some rewards
        vm.deal(address(stakeManager), totalRewardsAmount);
        vm.startPrank(address(stakeManager));
        mockWAPE.deposit{value: totalRewardsAmount}();
        mockWAPE.approve(address(coinPool), totalRewardsAmount);
        coinPool.receiveApeCoin(0, totalRewardsAmount);
        vm.stopPrank();

        // withdraw all coins
        for (userIndex = 0; userIndex < userCount; userIndex++) {
            vm.startPrank(testUsers[userIndex]);

            uint256 userBalanceBeforeWithdraw = coinPool.assetBalanceOf(testUsers[userIndex]);
            coinPool.withdraw(userBalanceBeforeWithdraw, testUsers[userIndex], testUsers[userIndex]);

            vm.stopPrank();
        }

        // check results
        for (userIndex = 0; userIndex < userCount; userIndex++) {
            uint256 userBalanceAfterWithdraw = mockWAPE.balanceOf(testUsers[userIndex]);
            assertGt(userBalanceAfterWithdraw, depositAmounts[userIndex], "user balance not match after withdraw");
        }
    }
}
