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

        mockApeCoin.mint(depositAmount);
        mockApeCoin.approve(address(coinPool), depositAmount);

        // deposit some coins
        coinPool.deposit(depositAmount, testUser);

        // withdraw all coins
        coinPool.withdraw(depositAmount, testUser, testUser);

        // check results
        uint256 userBalanceAfterWithdraw = mockApeCoin.balanceOf(testUser);
        assertEq(userBalanceAfterWithdraw, depositAmount, "user balance not match after withdraw");

        uint256 poolBalanceAfterWithdraw = mockApeCoin.balanceOf(address(coinPool));
        assertEq(poolBalanceAfterWithdraw, 0, "pool balance not match after withdraw");

        vm.stopPrank();
    }

    function testSingleUserDepositWithdrawHasRewards() public {
        address testUser = testUsers[0];
        uint256 depositAmount = 1000000 * 10 ** 18;
        uint256 rewardsAmount = 200000 * 10 ** 18;

        // deposit some coins
        vm.startPrank(testUser);
        mockApeCoin.mint(depositAmount);
        mockApeCoin.approve(address(coinPool), depositAmount);
        coinPool.deposit(depositAmount, testUser);
        vm.stopPrank();

        // make some rewards
        vm.startPrank(address(stakeManager));
        mockApeCoin.mint(rewardsAmount);
        mockApeCoin.approve(address(coinPool), rewardsAmount);
        coinPool.receiveApeCoin(0, rewardsAmount);
        vm.stopPrank();

        uint256 expectedUserBalanceAfterWithdraw = depositAmount + rewardsAmount;

        // withdraw all coins
        vm.startPrank(testUser);
        coinPool.withdraw(expectedUserBalanceAfterWithdraw, testUser, testUser);
        vm.stopPrank();

        // check results
        uint256 userBalanceAfterWithdraw = mockApeCoin.balanceOf(testUser);
        assertEq(userBalanceAfterWithdraw, expectedUserBalanceAfterWithdraw, "user balance not match after withdraw");

        uint256 poolBalanceAfterWithdraw = mockApeCoin.balanceOf(address(coinPool));
        assertEq(poolBalanceAfterWithdraw, 0, "pool balance not match after withdraw");
    }

    function testMutipleUserDepositWithdrawNoRewards() public {
        uint256 userIndex = 0;
        uint256 userCount = 3;
        uint256[] memory depositAmounts = new uint256[](userCount);

        for (userIndex = 0; userIndex < userCount; userIndex++) {
            vm.startPrank(testUsers[userIndex]);

            depositAmounts[userIndex] = 1000000 * 10 ** 18 * (userIndex + 1);
            mockApeCoin.mint(depositAmounts[userIndex]);
            mockApeCoin.approve(address(coinPool), depositAmounts[userIndex]);

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
            uint256 userBalanceAfterWithdraw = mockApeCoin.balanceOf(testUsers[userIndex]);
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

            mockApeCoin.mint(depositAmounts[userIndex]);
            mockApeCoin.approve(address(coinPool), depositAmounts[userIndex]);

            coinPool.deposit(depositAmounts[userIndex], testUsers[userIndex]);

            vm.stopPrank();
        }

        // make some rewards
        vm.startPrank(address(stakeManager));
        mockApeCoin.mint(totalRewardsAmount);
        mockApeCoin.approve(address(coinPool), totalRewardsAmount);
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
            uint256 expectedUserRewardAmount = (totalRewardsAmount * depositAmounts[userIndex]) / totalDepositAmount;
            uint256 expectedUserBalanceAfterWithdraw = (depositAmounts[userIndex] + expectedUserRewardAmount);

            uint256 userBalanceAfterWithdraw = mockApeCoin.balanceOf(testUsers[userIndex]);
            assertEq(
                userBalanceAfterWithdraw,
                expectedUserBalanceAfterWithdraw,
                "user balance not match after withdraw"
            );
        }
    }
}
