pragma solidity 0.8.18;

import "../../contracts/test/MockAaveLendPoolAddressesProvider.sol";
import "../../contracts/test/MockAaveLendPool.sol";
import "../../contracts/test/MockBendLendPoolAddressesProvider.sol";
import "../../contracts/test/MockBendLendPool.sol";
import "../../contracts/test/MockBendLendPoolLoan.sol";

import "../../contracts/misc/LendingMigrator.sol";

import "./SetupHelper.sol";

contract LendingMigratorTest is SetupHelper {
    MockAaveLendPoolAddressesProvider mockAaveLendPoolAddressesProvider;
    MockAaveLendPool mockAaveLendPool;
    MockBendLendPoolAddressesProvider mockBendLendPoolAddressesProvider;
    MockBendLendPool mockBendLendPool;
    MockBendLendPoolLoan mockBendLendPoolLoan;

    LendingMigrator lendingMigrator;

    struct TestLocalVars {
        uint256 i;
        uint256 j;
        uint256 nftCount;
        // bend lending vars
        address[] nftAssets;
        uint256[] nftTokenIds;
        uint256[] borrowAmounts;
        uint256[] bidFines;
        // results
        uint256 nftLoanId;
        address nftOwner;
        address nftBorrower;
    }

    function setUp() public override {
        super.setUp();

        mockAaveLendPoolAddressesProvider = new MockAaveLendPoolAddressesProvider();
        mockAaveLendPool = new MockAaveLendPool();
        mockAaveLendPoolAddressesProvider.setLendingPool(address(mockAaveLendPool));

        mockBendLendPoolAddressesProvider = new MockBendLendPoolAddressesProvider();
        mockBendLendPool = new MockBendLendPool();
        mockBendLendPoolLoan = new MockBendLendPoolLoan();
        mockBendLendPoolAddressesProvider.setLendPool(address(mockBendLendPool));
        mockBendLendPoolAddressesProvider.setLendPoolLoan(address(mockBendLendPoolLoan));
        mockBendLendPool.setAddressesProvider(address(mockBendLendPoolAddressesProvider));

        uint256 wethAmountAave = 1000000 * 10 ** 18;
        mockWETH.mint(wethAmountAave);
        mockWETH.transfer(address(mockAaveLendPool), wethAmountAave);

        uint256 usdtAmountAave = 1000000 * 10 ** 6;
        mockUSDT.mint(usdtAmountAave);
        mockUSDT.transfer(address(mockAaveLendPool), usdtAmountAave);

        uint256 wethAmountBend = 1000000 * 10 ** 18;
        mockWETH.mint(wethAmountBend);
        mockWETH.transfer(address(mockBendLendPool), wethAmountBend);

        uint256 usdtAmountBend = 1000000 * 10 ** 6;
        mockUSDT.mint(usdtAmountBend);
        mockUSDT.transfer(address(mockBendLendPool), usdtAmountBend);

        lendingMigrator = new LendingMigrator();
        lendingMigrator.initialize(
            address(mockAaveLendPoolAddressesProvider),
            address(mockBendLendPoolAddressesProvider),
            address(nftPool),
            address(stBAYC),
            address(stMAYC),
            address(stBAKC)
        );
    }

    function initTestLocalVars(TestLocalVars memory vars, uint256 nftCount) private pure {
        vars.nftCount = nftCount;
        vars.nftAssets = new address[](vars.nftCount);
        vars.nftTokenIds = new uint256[](vars.nftCount);
        vars.borrowAmounts = new uint256[](vars.nftCount);
        vars.bidFines = new uint256[](vars.nftCount);
    }

    function testMultipleNftWithoutAuction() public {
        TestLocalVars memory vars;
        address testUser = testUsers[0];

        initTestLocalVars(vars, 3);

        vm.startPrank(testUser);

        mockWETH.approve(address(mockBendLendPool), type(uint256).max);
        mockBAYC.setApprovalForAll(address(lendingMigrator), true);
        mockBAYC.setApprovalForAll(address(mockBendLendPool), true);

        for (vars.i = 0; vars.i < vars.nftCount; vars.i++) {
            vars.nftAssets[vars.i] = address(mockBAYC);
            vars.nftTokenIds[vars.i] = 100 + vars.i;

            // mint & borrow
            mockBAYC.mint(vars.nftTokenIds[vars.i]);

            vars.borrowAmounts[vars.i] = 1000 * 10 ** 18 + (vars.i + 1);
            mockBendLendPool.borrow(
                address(mockWETH),
                vars.borrowAmounts[vars.i],
                address(mockBAYC),
                vars.nftTokenIds[vars.i],
                testUser,
                0
            );
        }

        // migrate
        lendingMigrator.migrate(vars.nftAssets, vars.nftTokenIds);

        // check results
        for (vars.i = 0; vars.i < vars.nftCount; vars.i++) {
            vars.nftLoanId = mockBendLendPoolLoan.getCollateralLoanId(vars.nftAssets[vars.i], vars.nftTokenIds[vars.i]);

            vars.nftOwner = mockBAYC.ownerOf(vars.nftTokenIds[vars.i]);
            assertEq(vars.nftOwner, address(nftVault), "owner of original nft should be nft vault");

            vars.nftOwner = stBAYC.ownerOf(vars.nftTokenIds[vars.i]);
            assertEq(vars.nftOwner, address(mockBendLendPool), "owner of staked nft should be bend pool");

            vars.nftBorrower = mockBendLendPoolLoan.borrowerOf(vars.nftLoanId);
            assertEq(vars.nftBorrower, address(testUser), "borrower of loan should be test user");
        }

        vm.stopPrank();
    }

    function testMultipleNftWithAuction() public {
        TestLocalVars memory vars;
        address testUser = testUsers[0];

        initTestLocalVars(vars, 3);

        vm.startPrank(testUser);

        mockWETH.approve(address(mockBendLendPool), type(uint256).max);
        mockBAYC.setApprovalForAll(address(lendingMigrator), true);
        mockBAYC.setApprovalForAll(address(mockBendLendPool), true);

        for (vars.i = 0; vars.i < vars.nftCount; vars.i++) {
            vars.nftAssets[vars.i] = address(mockBAYC);
            vars.nftTokenIds[vars.i] = 100 + vars.i;

            // mint & borrow
            mockBAYC.mint(vars.nftTokenIds[vars.i]);

            vars.borrowAmounts[vars.i] = 1000 * 10 ** 18 + (vars.i + 1);
            mockBendLendPool.borrow(
                address(mockWETH),
                vars.borrowAmounts[vars.i],
                address(mockBAYC),
                vars.nftTokenIds[vars.i],
                testUser,
                0
            );
        }

        // set auction
        for (vars.i = 0; vars.i < vars.nftCount; vars.i++) {
            vars.nftLoanId = mockBendLendPoolLoan.getCollateralLoanId(vars.nftAssets[vars.i], vars.nftTokenIds[vars.i]);
            vars.bidFines[vars.i] = (vars.borrowAmounts[vars.i] * 5) / 100;
            mockBendLendPoolLoan.setBidFine(vars.nftLoanId, vars.bidFines[vars.i]);
        }

        // migrate
        lendingMigrator.migrate(vars.nftAssets, vars.nftTokenIds);

        // check results
        for (vars.i = 0; vars.i < vars.nftCount; vars.i++) {
            vars.nftLoanId = mockBendLendPoolLoan.getCollateralLoanId(vars.nftAssets[vars.i], vars.nftTokenIds[vars.i]);

            vars.nftOwner = mockBAYC.ownerOf(vars.nftTokenIds[vars.i]);
            assertEq(vars.nftOwner, address(nftVault), "owner of original nft should be nft vault");

            vars.nftOwner = stBAYC.ownerOf(vars.nftTokenIds[vars.i]);
            assertEq(vars.nftOwner, address(mockBendLendPool), "owner of staked nft should be bend pool");

            vars.nftBorrower = mockBendLendPoolLoan.borrowerOf(vars.nftLoanId);
            assertEq(vars.nftBorrower, address(testUser), "borrower of loan should be test user");
        }

        vm.stopPrank();
    }
}
