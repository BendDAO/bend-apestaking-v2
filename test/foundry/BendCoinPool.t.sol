pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendCoinPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function testSingleUserDepositWithdrawNoRewards() public {
        super.initTestVars(1);
        testVars.curUser = testUsers[0];

        vm.startPrank(testUsers[0]);

        testVars.depositAmounts[0] = 1000000 * 10**18;
        mockApeCoin.mint(testVars.depositAmounts[0]);
        mockApeCoin.approve(address(coinPool), testVars.depositAmounts[0]);

        // deposit some coins
        CoinPoolData memory poolDataBeforeDeposit = getCoinPoolDataInContracts();
        CoinUserData memory userDataBeforeDeposit = getCoinUserDataInContracts(testVars.curUser);

        coinPool.deposit(testVars.depositAmounts[0], testVars.curUser);

        // check results
        CoinPoolData memory poolDataAfterDeposit = getCoinPoolDataInContracts();
        CoinUserData memory userDataAfterDeposit = getCoinUserDataInContracts(testVars.curUser);

        CoinPoolData memory poolDataExpectedAfterDeposit = calcExpectedCoinPoolDataAfterDeposit(
            testVars.curUser,
            testVars.depositAmounts[0],
            poolDataBeforeDeposit,
            userDataBeforeDeposit
        );
        CoinUserData memory userDataExpectedAfterDeposit = calcExpectedCoinUserDataAfterDeposit(
            testVars.curUser,
            testVars.depositAmounts[0],
            poolDataBeforeDeposit,
            userDataBeforeDeposit
        );

        assertEq(poolDataAfterDeposit.totalAssets, poolDataExpectedAfterDeposit.totalAssets, "total assets not match");
        assertEq(poolDataAfterDeposit.totalShares, poolDataExpectedAfterDeposit.totalShares, "total shares not match");
        assertEq(userDataAfterDeposit.totalAssets, userDataExpectedAfterDeposit.totalAssets, "user assets not match");
        assertEq(userDataAfterDeposit.totalShares, userDataExpectedAfterDeposit.totalShares, "user shares not match");

        // withdraw all coins
        CoinPoolData memory poolDataBeforeWithdraw = getCoinPoolDataInContracts();
        CoinUserData memory userDataBeforeWithdraw = getCoinUserDataInContracts(testVars.curUser);

        testVars.withdrawAmounts[0] = coinPool.assetBalanceOf(testVars.curUser);
        coinPool.withdraw(testVars.withdrawAmounts[0], testVars.curUser, testVars.curUser);

        // check results
        CoinPoolData memory poolDataAfterWithdraw = getCoinPoolDataInContracts();
        CoinUserData memory userDataAfterWithdraw = getCoinUserDataInContracts(testVars.curUser);

        CoinPoolData memory poolDataExpectedAfterWithdraw = calcExpectedCoinPoolDataAfterWithdraw(
            testVars.curUser,
            testVars.withdrawAmounts[0],
            poolDataBeforeWithdraw,
            userDataBeforeWithdraw
        );
        CoinUserData memory userDataExpectedAfterWithdraw = calcExpectedCoinUserDataAfterWithdraw(
            testVars.curUser,
            testVars.withdrawAmounts[0],
            poolDataBeforeWithdraw,
            userDataBeforeWithdraw
        );

        assertEq(
            poolDataAfterWithdraw.totalAssets,
            poolDataExpectedAfterWithdraw.totalAssets,
            "total assets not match"
        );
        assertEq(
            poolDataAfterWithdraw.totalShares,
            poolDataExpectedAfterWithdraw.totalShares,
            "total shares not match"
        );
        assertEq(userDataAfterWithdraw.totalAssets, userDataExpectedAfterWithdraw.totalAssets, "user assets not match");
        assertEq(userDataAfterWithdraw.totalShares, userDataExpectedAfterWithdraw.totalShares, "user shares not match");

        vm.stopPrank();
    }

    function testSingleUserDepositWithdrawHasRewards() public {
        super.initTestVars(1);
        testVars.curUser = testUsers[0];

        vm.startPrank(testVars.curUser);

        testVars.depositAmounts[0] = 1000000 * 10**18;
        mockApeCoin.mint(testVars.depositAmounts[0]);
        mockApeCoin.approve(address(coinPool), testVars.depositAmounts[0]);

        // deposit some coins
        CoinPoolData memory poolDataBeforeDeposit = getCoinPoolDataInContracts();
        CoinUserData memory userDataBeforeDeposit = getCoinUserDataInContracts(testVars.curUser);

        coinPool.deposit(testVars.depositAmounts[0], testVars.curUser);

        // check results
        CoinPoolData memory poolDataAfterDeposit = getCoinPoolDataInContracts();
        CoinUserData memory userDataAfterDeposit = getCoinUserDataInContracts(testVars.curUser);

        CoinPoolData memory poolDataExpectedAfterDeposit = calcExpectedCoinPoolDataAfterDeposit(
            testVars.curUser,
            testVars.depositAmounts[0],
            poolDataBeforeDeposit,
            userDataBeforeDeposit
        );
        CoinUserData memory userDataExpectedAfterDeposit = calcExpectedCoinUserDataAfterDeposit(
            testVars.curUser,
            testVars.depositAmounts[0],
            poolDataBeforeDeposit,
            userDataBeforeDeposit
        );

        assertEq(poolDataAfterDeposit.totalAssets, poolDataExpectedAfterDeposit.totalAssets, "total assets not match");
        assertEq(poolDataAfterDeposit.totalShares, poolDataExpectedAfterDeposit.totalShares, "total shares not match");
        assertEq(userDataAfterDeposit.totalAssets, userDataExpectedAfterDeposit.totalAssets, "user assets not match");
        assertEq(userDataAfterDeposit.totalShares, userDataExpectedAfterDeposit.totalShares, "user shares not match");

        vm.stopPrank();

        // do some stake
        vm.startPrank(botAdmin);

        IStakeManager.CompoundArgs memory compoundArgs1;
        compoundArgs1.coinStakeThreshold = 0;
        stakeManager.compound(compoundArgs1);

        // make some rewards
        advanceTimeAndBlock(2 hours, 100);

        testVars.expectedCoinRewards[0] = calcExpectedCoinPendingRewards();

        IStakeManager.CompoundArgs memory compoundArgs2;
        compoundArgs2.coinStakeThreshold = 0;
        compoundArgs2.claimCoinPool = true;
        stakeManager.compound(compoundArgs2);

        vm.stopPrank();

        testVars.queriedCoinStakedAmounts[0] = getCoinStakedAmountInContracts();

        // withdraw all coins
        vm.startPrank(testVars.curUser);

        CoinPoolData memory poolDataBeforeWithdraw = getCoinPoolDataInContracts();
        CoinUserData memory userDataBeforeWithdraw = getCoinUserDataInContracts(testVars.curUser);

        testVars.withdrawAmounts[0] = coinPool.assetBalanceOf(testVars.curUser);
        coinPool.withdraw(testVars.withdrawAmounts[0], testVars.curUser, testVars.curUser);

        // check results
        assertEq(
            (testVars.depositAmounts[0] + testVars.expectedCoinRewards[0]),
            testVars.queriedCoinStakedAmounts[0],
            "staked amount not match"
        );
        assertEq(
            (testVars.depositAmounts[0] + testVars.expectedCoinRewards[0]),
            testVars.withdrawAmounts[0],
            "withdraw amount not match"
        );

        CoinPoolData memory poolDataAfterWithdraw = getCoinPoolDataInContracts();
        CoinUserData memory userDataAfterWithdraw = getCoinUserDataInContracts(testVars.curUser);

        CoinPoolData memory poolDataExpectedAfterWithdraw = calcExpectedCoinPoolDataAfterWithdraw(
            testVars.curUser,
            testVars.withdrawAmounts[0],
            poolDataBeforeWithdraw,
            userDataBeforeWithdraw
        );
        CoinUserData memory userDataExpectedAfterWithdraw = calcExpectedCoinUserDataAfterWithdraw(
            testVars.curUser,
            testVars.withdrawAmounts[0],
            poolDataBeforeWithdraw,
            userDataBeforeWithdraw
        );

        assertEq(
            poolDataAfterWithdraw.totalAssets,
            poolDataExpectedAfterWithdraw.totalAssets,
            "total assets not match"
        );
        assertEq(
            poolDataAfterWithdraw.totalShares,
            poolDataExpectedAfterWithdraw.totalShares,
            "total shares not match"
        );
        assertEq(userDataAfterWithdraw.totalAssets, userDataExpectedAfterWithdraw.totalAssets, "user assets not match");
        assertEq(userDataAfterWithdraw.totalShares, userDataExpectedAfterWithdraw.totalShares, "user shares not match");

        vm.stopPrank();
    }

    function testMutipleUserDepositWithdrawNoRewards() public {
        super.initTestVars(5);

        for (testVars.userIndex = 0; testVars.userIndex < 5; testVars.userIndex++) {
            vm.startPrank(testUsers[testVars.userIndex]);

            testVars.depositAmounts[testVars.userIndex] = 1000000 * 10**18 * (testVars.userIndex + 1);
            mockApeCoin.mint(testVars.depositAmounts[testVars.userIndex]);
            mockApeCoin.approve(address(coinPool), testVars.depositAmounts[testVars.userIndex]);

            coinPool.deposit(testVars.depositAmounts[testVars.userIndex], testUsers[testVars.userIndex]);

            vm.stopPrank();
        }

        for (testVars.userIndex = 0; testVars.userIndex < 5; testVars.userIndex++) {
            vm.startPrank(testUsers[testVars.userIndex]);

            coinPool.withdraw(
                testVars.depositAmounts[testVars.userIndex],
                testUsers[testVars.userIndex],
                testUsers[testVars.userIndex]
            );

            vm.stopPrank();
        }
    }

    function testMutipleUserDepositWithdrawHasRewards() public {
        super.initTestVars(5);

        for (testVars.userIndex = 0; testVars.userIndex < 5; testVars.userIndex++) {
            vm.startPrank(testUsers[testVars.userIndex]);

            testVars.depositAmounts[testVars.userIndex] = 1000000 * 10**18 * (testVars.userIndex + 1);
            mockApeCoin.mint(testVars.depositAmounts[testVars.userIndex]);
            mockApeCoin.approve(address(coinPool), testVars.depositAmounts[testVars.userIndex]);

            coinPool.deposit(testVars.depositAmounts[testVars.userIndex], testUsers[testVars.userIndex]);

            vm.stopPrank();
        }

        botStakeCoinPool();

        advanceTimeAndBlock(2 hours, 100);

        testVars.expectedCoinRewards[0] = botCompoudCoinPool();
        assertGt(testVars.expectedCoinRewards[0], 0, "coin rewards is zer0");

        for (testVars.userIndex = 0; testVars.userIndex < 5; testVars.userIndex++) {
            vm.startPrank(testUsers[testVars.userIndex]);

            testVars.tmpUint256A = coinPool.assetBalanceOf(testUsers[testVars.userIndex]);
            coinPool.withdraw(testVars.tmpUint256A, testUsers[testVars.userIndex], testUsers[testVars.userIndex]);

            testVars.balanceAmounts[testVars.userIndex] = mockApeCoin.balanceOf(testUsers[testVars.userIndex]);
            assertGt(
                testVars.balanceAmounts[testVars.userIndex],
                testVars.depositAmounts[testVars.userIndex],
                "balance not match"
            );

            vm.stopPrank();
        }
    }
}
