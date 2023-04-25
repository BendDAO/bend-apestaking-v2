pragma solidity 0.8.18;

import "./SetupHelper.sol";

contract BendCoinPoolTest is SetupHelper {
    function setUp() public override {
        super.setUp();
    }

    function test_deposit() public {
        address user = users[0];
        vm.startPrank(user);

        IApeCoinStaking.PoolWithoutTimeRange memory pool = IApeCoinStaking(address(mockApeStaking)).pools(1);

        uint256 depositAmount = 1000000 * 10**18;
        mockApeCoin.mint(depositAmount);
        mockApeCoin.approve(address(coinPool), depositAmount);

        coinPool.deposit(depositAmount, user);
    }

    function test_RevertWhen_BalanceNotEnough() public {
        address user = users[0];
        vm.startPrank(user);

        vm.expectRevert("hahah");
        coinPool.deposit(1000 * 10**18, user);
    }
}
