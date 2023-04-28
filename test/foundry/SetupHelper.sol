pragma solidity 0.8.18;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "../../contracts/test/MintableERC20.sol";
import "../../contracts/test/MintableERC721.sol";
import "../../contracts/test/ApeCoinStaking.sol";
import "../../contracts/test/DelegationRegistry.sol";

import "../../contracts/interfaces/IDelegationRegistry.sol";
import "../../contracts/interfaces/IApeCoinStaking.sol";
import "../../contracts/interfaces/IStakedNft.sol";
import "../../contracts/interfaces/INftVault.sol";
import "../../contracts/interfaces/ICoinPool.sol";
import "../../contracts/interfaces/INftPool.sol";
import "../../contracts/interfaces/IStakeManager.sol";
import "../../contracts/interfaces/IRewardsStrategy.sol";

import "../../contracts/stakednft/NftVault.sol";
import "../../contracts/stakednft/StBAYC.sol";
import "../../contracts/stakednft/StMAYC.sol";
import "../../contracts/stakednft/StBAKC.sol";

import "../../contracts/BendCoinPool.sol";
import "../../contracts/BendNftPool.sol";
import "../../contracts/BendStakeManager.sol";

import "../../contracts/strategy/BaycStrategy.sol";
import "../../contracts/strategy/MaycStrategy.sol";
import "../../contracts/strategy/BakcStrategy.sol";

import "./UtilitiesHelper.sol";

abstract contract SetupHelper is Test {
    // types
    struct TestLocalVars {
        uint256 userAmount;
        address curUser;
        uint256 curTokenId;
        uint256 userIndex;
        uint256 nftIndex;
        uint256 loopIndex1;
        uint256 loopIndex2;
        uint256 tmpUint256A;
        uint256 tmpUint256B;
        uint256[] balanceAmounts;
        uint256[] depositAmounts;
        uint256[] withdrawAmounts;
        uint256[] queriedCoinStakedAmounts;
        uint256[] queriedOneNftStakedAmounts;
        uint256[] queriedAllNftStakedAmounts;
        uint256[] expectedCoinStakedAmounts;
        uint256[] expectedOneNftStakedAmounts;
        uint256[] expectedAllNftStakedAmounts;
        uint256[] expectedCoinRewards;
        uint256[] expectedOneNftRewards;
        uint256[] expectedAllNftRewards;
    }

    struct CoinPoolData {
        uint256 totalShares;
        uint256 totalAssets;
    }
    struct CoinUserData {
        uint256 totalShares;
        uint256 totalAssets;
    }
    struct NftPoolData {
        uint256 totalNftAmount;
        uint256 accumulatedRewardsPerNft;
    }
    struct NftTokenData {
        uint256 rewardsDebt;
        uint256 claimableRewards;
    }

    UtilitiesHelper internal utilsHelper;

    // mocked users
    address payable[] internal testUsers;
    address payable testUser0;
    address payable[] internal adminOwners;
    address payable poolOwner;
    address payable botAdmin;

    // mocked contracts
    MintableERC20 internal mockApeCoin;
    MintableERC721 internal mockBAYC;
    MintableERC721 internal mockMAYC;
    MintableERC721 internal mockBAKC;
    ApeCoinStaking internal mockApeStaking;
    DelegationRegistry internal mockDelegationRegistry;

    // tested contracts
    NftVault internal nftVault;
    StBAYC internal stBAYC;
    StMAYC internal stMAYC;
    StBAKC internal stBAKC;

    BendCoinPool internal coinPool;
    BendNftPool internal nftPool;
    BendStakeManager internal stakeManager;
    BaycStrategy internal baycStrategy;
    MaycStrategy internal maycStrategy;
    BakcStrategy internal bakcStrategy;

    // mocked datas
    uint256[] internal testBaycTokenIds;
    uint256[] internal testMaycTokenIds;
    uint256[] internal testBakcTokenIds;

    TestLocalVars internal testVars;

    function setUp() public virtual {
        // prepare test users
        utilsHelper = new UtilitiesHelper();

        testUsers = utilsHelper.createUsers(5);
        testUser0 = testUsers[0];

        adminOwners = utilsHelper.createUsers(5);
        poolOwner = adminOwners[0];
        botAdmin = adminOwners[1];

        mockDelegationRegistry = new DelegationRegistry();

        // mocked ERC20 and NFTs
        mockApeCoin = new MintableERC20("ApeCoin", "APE", 18);

        mockBAYC = new MintableERC721("Mock BAYC", "BAYC");
        mockMAYC = new MintableERC721("Mock MAYC", "MAYC");
        mockBAKC = new MintableERC721("Mock BAKC", "BAKC");

        // mocked ape staking and config params
        mockApeStaking = new ApeCoinStaking(
            address(mockApeCoin),
            address(mockBAYC),
            address(mockMAYC),
            address(mockBAKC)
        );
        // ApeCoin pool
        mockApeStaking.addTimeRange(0, 10500000000000000000000000, 1669748400, 1677610800, 0);
        mockApeStaking.addTimeRange(0, 9000000000000000000000000, 1677610800, 1685559600, 0);
        mockApeStaking.addTimeRange(0, 6000000000000000000000000, 1685559600, 1693422000, 0);
        mockApeStaking.addTimeRange(0, 4500000000000000000000000, 1693422000, 1701284400, 0);
        // BAYC pool
        mockApeStaking.addTimeRange(1, 16486750000000000000000000, 1669748400, 1677610800, 10094000000000000000000);
        mockApeStaking.addTimeRange(1, 14131500000000000000000000, 1677610800, 1685559600, 10094000000000000000000);
        mockApeStaking.addTimeRange(1, 9421000000000000000000000, 1685559600, 1693422000, 10094000000000000000000);
        mockApeStaking.addTimeRange(1, 7065750000000000000000000, 1693422000, 1701284400, 10094000000000000000000);
        // MAYC pool
        mockApeStaking.addTimeRange(2, 6671000000000000000000000, 1669748400, 1677610800, 2042000000000000000000);
        mockApeStaking.addTimeRange(2, 5718000000000000000000000, 1677610800, 1685559600, 2042000000000000000000);
        mockApeStaking.addTimeRange(2, 3812000000000000000000000, 1685559600, 1693422000, 2042000000000000000000);
        mockApeStaking.addTimeRange(2, 2859000000000000000000000, 1693422000, 1701284400, 2042000000000000000000);
        // BAKC pool
        mockApeStaking.addTimeRange(3, 1342250000000000000000000, 1669748400, 1677610800, 856000000000000000000);
        mockApeStaking.addTimeRange(3, 1150500000000000000000000, 1677610800, 1685559600, 856000000000000000000);
        mockApeStaking.addTimeRange(3, 767000000000000000000000, 1685559600, 1693422000, 856000000000000000000);
        mockApeStaking.addTimeRange(3, 575250000000000000000000, 1693422000, 1701284400, 856000000000000000000);

        // staked nfts
        nftVault = new NftVault(IApeCoinStaking(address(mockApeStaking)), IDelegationRegistry(mockDelegationRegistry));
        stBAYC = new StBAYC(mockBAYC, nftVault);
        stMAYC = new StMAYC(mockMAYC, nftVault);
        stBAKC = new StBAKC(mockBAKC, nftVault);

        // staking contracts
        coinPool = new BendCoinPool();
        nftPool = new BendNftPool();
        stakeManager = new BendStakeManager();

        coinPool.initialize(IApeCoinStaking(address(mockApeStaking)), stakeManager);
        nftPool.initialize(
            IApeCoinStaking(address(mockApeStaking)),
            IDelegationRegistry(mockDelegationRegistry),
            coinPool,
            stakeManager,
            stBAYC,
            stMAYC,
            stBAKC
        );
        stakeManager.initialize(IApeCoinStaking(address(mockApeStaking)), coinPool, nftPool, nftVault);

        // set the strategy contracts
        baycStrategy = new BaycStrategy();
        maycStrategy = new MaycStrategy();
        bakcStrategy = new BakcStrategy();
        stakeManager.updateRewardsStrategy(address(mockBAYC), IRewardsStrategy(baycStrategy));
        stakeManager.updateRewardsStrategy(address(mockMAYC), IRewardsStrategy(maycStrategy));
        stakeManager.updateRewardsStrategy(address(mockBAKC), IRewardsStrategy(bakcStrategy));

        // mint some coins
        uint256 totalCoinRewards = 100000000 * 1e18;
        mockApeCoin.mint(totalCoinRewards);
        mockApeCoin.transfer(address(mockApeStaking), totalCoinRewards);

        // changing the owner and admin
        vm.startPrank(coinPool.owner());
        coinPool.transferOwnership(poolOwner);
        nftPool.transferOwnership(poolOwner);
        stakeManager.transferOwnership(poolOwner);
        vm.stopPrank();

        vm.startPrank(stakeManager.owner());
        stakeManager.updateBotAdmin(botAdmin);
        vm.stopPrank();

        // update the block info
        vm.warp(1669748400);
        vm.roll(100);
    }

    function initTestVars(uint256 userAmount) internal {
        testVars.userAmount = userAmount;
        testVars.curUser = address(0);
        testVars.curTokenId = 0;
        testVars.userIndex = 0;
        testVars.nftIndex = 0;
        testVars.loopIndex1 = 0;
        testVars.loopIndex2 = 0;

        testVars.balanceAmounts = new uint256[](userAmount);
        testVars.depositAmounts = new uint256[](userAmount);
        testVars.withdrawAmounts = new uint256[](userAmount);
        testVars.queriedCoinStakedAmounts = new uint256[](userAmount);
        testVars.queriedOneNftStakedAmounts = new uint256[](userAmount);
        testVars.queriedAllNftStakedAmounts = new uint256[](userAmount);
        testVars.expectedCoinStakedAmounts = new uint256[](userAmount);
        testVars.expectedOneNftStakedAmounts = new uint256[](userAmount);
        testVars.expectedAllNftStakedAmounts = new uint256[](userAmount);
        testVars.expectedCoinRewards = new uint256[](userAmount);
        testVars.expectedOneNftRewards = new uint256[](userAmount);
        testVars.expectedAllNftRewards = new uint256[](userAmount);
    }

    function advanceTime(uint256 timeDelta) internal {
        vm.warp(block.timestamp + timeDelta);
    }

    function advanceBlock(uint256 blockDelta) internal {
        vm.roll(block.number + blockDelta);
    }

    function advanceTimeAndBlock(uint256 timeDelta, uint256 blockDelta) internal {
        vm.warp(block.timestamp + timeDelta);
        vm.roll(block.number + blockDelta);
    }

    function prepareAllApprovals(address user) internal virtual {
        vm.startPrank(user);

        mockApeCoin.approve(address(coinPool), type(uint256).max);

        mockBAYC.setApprovalForAll(address(nftPool), true);
        mockMAYC.setApprovalForAll(address(nftPool), true);
        mockBAKC.setApprovalForAll(address(nftPool), true);

        stBAYC.setApprovalForAll(address(nftPool), true);
        stMAYC.setApprovalForAll(address(nftPool), true);
        stBAKC.setApprovalForAll(address(nftPool), true);

        vm.stopPrank();
    }

    function prepareMintCoins(address user, uint256 depositAmount) internal virtual {
        vm.startPrank(user);
        mockApeCoin.mint(depositAmount);
        vm.stopPrank();
    }

    function prepareDepositCoins(address user, uint256 depositAmount) internal virtual {
        prepareMintCoins(user, depositAmount);

        vm.startPrank(user);
        coinPool.deposit(depositAmount, user);
        vm.stopPrank();
    }

    function prepareMintNfts(address user, uint256 tokenAmount) internal virtual {
        vm.startPrank(user);

        testBaycTokenIds = new uint256[](tokenAmount);
        for (uint256 i = 0; i < tokenAmount; i++) {
            testBaycTokenIds[i] = 101 + i;
            mockBAYC.mint(testBaycTokenIds[i]);
        }

        testMaycTokenIds = new uint256[](tokenAmount);
        for (uint256 i = 0; i < testMaycTokenIds.length; i++) {
            testMaycTokenIds[i] = 201 + i;
            mockMAYC.mint(testMaycTokenIds[i]);
        }

        testBakcTokenIds = new uint256[](tokenAmount);
        for (uint256 i = 0; i < tokenAmount; i++) {
            testBakcTokenIds[i] = 301 + i;
            mockBAKC.mint(testBakcTokenIds[i]);
        }

        vm.stopPrank();
    }

    function prepareDepositNfts(address user, uint256 tokenAmount) internal virtual {
        prepareMintNfts(user, tokenAmount);

        vm.startPrank(user);
        nftPool.deposit(address(mockBAYC), testBaycTokenIds);
        nftPool.deposit(address(mockMAYC), testMaycTokenIds);
        nftPool.deposit(address(mockBAKC), testBakcTokenIds);
        vm.stopPrank();
    }

    function botStakeCoinPool() internal {
        vm.startPrank(botAdmin);

        IStakeManager.CompoundArgs memory compoundArgs;
        compoundArgs.coinStakeThreshold = 0;
        stakeManager.compound(compoundArgs);

        vm.stopPrank();
    }

    function botClaimCoinPool() internal returns (uint256 expectedRewards) {
        vm.startPrank(botAdmin);

        expectedRewards = calcExpectedCoinPendingRewards();

        IStakeManager.CompoundArgs memory compoundArgs;
        compoundArgs.claimCoinPool = true;
        compoundArgs.coinStakeThreshold = type(uint256).max;
        stakeManager.compound(compoundArgs);

        vm.stopPrank();
    }

    function botCompoudCoinPool() internal returns (uint256 expectedRewards) {
        vm.startPrank(botAdmin);

        expectedRewards = calcExpectedCoinPendingRewards();

        IStakeManager.CompoundArgs memory compoundArgs;
        compoundArgs.claimCoinPool = true;
        compoundArgs.coinStakeThreshold = 0;
        stakeManager.compound(compoundArgs);

        vm.stopPrank();
    }

    // query data in contracts

    function getCoinPoolDataInContracts() internal view returns (CoinPoolData memory poolData) {
        poolData.totalShares = coinPool.totalSupply();
        poolData.totalAssets = coinPool.totalAssets();
    }

    function getCoinUserDataInContracts(address user) internal view returns (CoinUserData memory userData) {
        userData.totalShares = coinPool.balanceOf(user);
        userData.totalAssets = coinPool.assetBalanceOf(user);
    }

    function getNftPoolDataInContracts(address nft) internal view returns (NftPoolData memory poolData) {
        (poolData.totalNftAmount, poolData.accumulatedRewardsPerNft) = nftPool.getPoolStateUI(nft);
    }

    function getNftTokenDataInContracts(address nft, uint256 tokenId)
        internal
        view
        returns (NftTokenData memory tokenData)
    {
        tokenData.rewardsDebt = nftPool.getNftStateUI(nft, tokenId);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        tokenData.claimableRewards = nftPool.claimable(nft, tokenIds);
    }

    function getCoinStakedAmountInContracts() internal view returns (uint256) {
        IApeCoinStaking.Position memory position = IApeCoinStaking(address(mockApeStaking)).addressPosition(
            address(stakeManager)
        );
        return position.stakedAmount;
    }

    function getOneNftStakedAmountInContracts(uint256 poolId, uint256 tokenId) internal view returns (uint256) {
        IApeCoinStaking.Position memory position = IApeCoinStaking(address(mockApeStaking)).nftPosition(
            poolId,
            tokenId
        );
        return position.stakedAmount;
    }

    // calculate expected data for coin pool

    function calcExpectedCoinPendingRewards() internal view returns (uint256) {
        return mockApeStaking.pendingRewards(0, address(stakeManager), 0);
    }

    function calcExpectedNftPendingRewards(uint256 poolId, uint256[] calldata tokenIds)
        internal
        view
        returns (uint256)
    {
        uint256 rewardsAmount = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            rewardsAmount += mockApeStaking.pendingRewards(poolId, address(nftVault), tokenIds[i]);
        }
        return rewardsAmount;
    }

    function calcExpectedCoinPoolDataAfterDeposit(
        address, /*user*/
        uint256 depositAmount,
        CoinPoolData memory poolDataBefore,
        CoinUserData memory /*userDataBefore*/
    ) internal pure returns (CoinPoolData memory poolDataExpected) {
        uint256 sharesDelta = convertAssetsToShares(
            depositAmount,
            poolDataBefore.totalShares,
            poolDataBefore.totalAssets,
            Math.Rounding.Down
        );

        poolDataExpected.totalShares = poolDataBefore.totalShares + sharesDelta;
        poolDataExpected.totalAssets = poolDataBefore.totalAssets + depositAmount;
    }

    function calcExpectedCoinUserDataAfterDeposit(
        address, /*user*/
        uint256 depositAmount,
        CoinPoolData memory poolDataBefore,
        CoinUserData memory userDataBefore
    ) internal pure returns (CoinUserData memory userDataExpected) {
        uint256 sharesDelta = convertAssetsToShares(
            depositAmount,
            poolDataBefore.totalShares,
            poolDataBefore.totalAssets,
            Math.Rounding.Down
        );

        userDataExpected.totalShares = poolDataBefore.totalShares + sharesDelta;
        userDataExpected.totalAssets = userDataBefore.totalAssets + depositAmount;
    }

    function calcExpectedCoinPoolDataAfterWithdraw(
        address, /*user*/
        uint256 withdrawAmount,
        CoinPoolData memory poolDataBefore,
        CoinUserData memory /*userDataBefore*/
    ) internal pure returns (CoinPoolData memory poolDataExpected) {
        uint256 sharesDelta = convertAssetsToShares(
            withdrawAmount,
            poolDataBefore.totalShares,
            poolDataBefore.totalAssets,
            Math.Rounding.Down
        );

        poolDataExpected.totalShares = poolDataBefore.totalShares - sharesDelta;
        poolDataExpected.totalAssets = poolDataBefore.totalAssets - withdrawAmount;
    }

    function calcExpectedCoinUserDataAfterWithdraw(
        address, /*user*/
        uint256 withdrawAmount,
        CoinPoolData memory poolDataBefore,
        CoinUserData memory userDataBefore
    ) internal pure returns (CoinUserData memory userDataExpected) {
        uint256 sharesDelta = convertAssetsToShares(
            withdrawAmount,
            poolDataBefore.totalShares,
            poolDataBefore.totalAssets,
            Math.Rounding.Down
        );

        userDataExpected.totalShares = poolDataBefore.totalShares - sharesDelta;
        userDataExpected.totalAssets = userDataBefore.totalAssets - withdrawAmount;
    }

    function calcExpectedCoinPoolDataAfterDistributeReward(
        uint256 rewardsAmount,
        CoinPoolData memory poolDataBefore,
        CoinUserData memory userDataBefore
    ) internal pure returns (CoinPoolData memory poolDataExpected) {
        poolDataExpected.totalShares = poolDataBefore.totalShares;
        poolDataExpected.totalAssets = poolDataBefore.totalAssets + rewardsAmount;
    }

    function calcExpectedCoinUserDataAfterDistributeReward(
        uint256 rewardsAmount,
        CoinPoolData memory poolDataBefore,
        CoinUserData memory userDataBefore
    ) internal pure returns (CoinUserData memory userDataExpected) {
        uint256 assetsDelata = Math.mulDiv(
            userDataBefore.totalShares,
            poolDataBefore.totalAssets,
            poolDataBefore.totalShares,
            Math.Rounding.Down
        );

        userDataExpected.totalShares = userDataBefore.totalShares;
        userDataExpected.totalAssets = userDataBefore.totalAssets + assetsDelata;
    }

    // calculate expected data for nft pool
    function calcExpectedNftPoolDataAfterDeposit(
        address nft,
        uint256 tokenId,
        NftPoolData memory poolDataBefore,
        NftTokenData memory tokenDataBefore
    ) internal pure returns (NftPoolData memory poolDataExpected) {
        poolDataExpected.accumulatedRewardsPerNft = poolDataBefore.accumulatedRewardsPerNft;
        poolDataExpected.totalNftAmount = poolDataBefore.totalNftAmount + 1;
    }

    function calcExpectedNftTokenDataAfterDeposit(
        address nft,
        uint256 tokenId,
        NftPoolData memory poolDataBefore,
        NftTokenData memory tokenDataBefore
    ) internal pure returns (NftTokenData memory tokenDataExpected) {
        tokenDataExpected.rewardsDebt = poolDataBefore.accumulatedRewardsPerNft;
        tokenDataExpected.claimableRewards = 0;
    }

    function calcExpectedNftPoolDataAfterWithdraw(
        address nft,
        uint256 tokenId,
        NftPoolData memory poolDataBefore,
        NftTokenData memory tokenDataBefore
    ) internal pure returns (NftPoolData memory poolDataExpected) {
        poolDataExpected.accumulatedRewardsPerNft = poolDataBefore.accumulatedRewardsPerNft;
        poolDataExpected.totalNftAmount = poolDataBefore.totalNftAmount - 1;
    }

    function calcExpectedNftTokenDataAfterWithdraw(
        address nft,
        uint256 tokenId,
        NftPoolData memory poolDataBefore,
        NftTokenData memory tokenDataBefore
    ) internal pure returns (NftTokenData memory tokenDataExpected) {
        tokenDataExpected.rewardsDebt = 0;
        tokenDataExpected.claimableRewards = 0;
    }

    function calcExpectedNftPoolDataAfterDistributeReward(
        address nft,
        uint256 rewardsAmount,
        NftPoolData memory poolDataBefore
    ) internal pure returns (NftPoolData memory poolDataExpected) {
        uint256 accRewardsPerNftDelta = (rewardsAmount * 1e18) / poolDataBefore.totalNftAmount;
        poolDataExpected.accumulatedRewardsPerNft = poolDataBefore.accumulatedRewardsPerNft + accRewardsPerNftDelta;
        poolDataExpected.totalNftAmount = poolDataBefore.totalNftAmount;
    }

    function calcExpectedNftTokenDataAfterDistributeReward(
        address nft,
        uint256 rewardsAmount,
        NftPoolData memory poolDataBefore,
        NftTokenData memory tokenDataBefore,
        NftPoolData memory poolDataAfter
    ) internal pure returns (NftTokenData memory tokenDataExpected) {
        tokenDataExpected.rewardsDebt = poolDataBefore.accumulatedRewardsPerNft;
        uint256 accRewardsPerNftDelta = (poolDataAfter.accumulatedRewardsPerNft - tokenDataBefore.rewardsDebt) / 1e18;
        tokenDataExpected.claimableRewards += accRewardsPerNftDelta;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function convertAssetsToShares(
        uint256 assets,
        uint256 totaShares,
        uint256 totalAssets,
        Math.Rounding rounding
    ) internal pure returns (uint256) {
        return Math.mulDiv(assets, totaShares + 10**0, totalAssets + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function convertSharesToAssets(
        uint256 shares,
        uint256 totaShares,
        uint256 totalAssets,
        Math.Rounding rounding
    ) internal pure returns (uint256) {
        return Math.mulDiv(shares, totalAssets + 1, totaShares + 10**0, rounding);
    }
}
