pragma solidity 0.8.18;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "../../contracts/test/MintableERC20.sol";
import "../../contracts/test/MintableERC721.sol";
import "../../contracts/test/ApeCoinStaking.sol";
import "../../contracts/test/DelegationRegistry.sol";
import "../../contracts/test/MockBNFTRegistry.sol";
import "../../contracts/test/MockBNFT.sol";

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
    UtilitiesHelper internal utilsHelper;

    // mocked users
    address payable[] internal testUsers;
    address payable testUser0;
    address payable[] internal adminOwners;
    address payable poolOwner;
    address payable botAdmin;

    // mocked contracts
    MintableERC20 internal mockWETH;
    MintableERC20 internal mockUSDT;
    MintableERC20 internal mockApeCoin;
    MintableERC721 internal mockBAYC;
    MintableERC721 internal mockMAYC;
    MintableERC721 internal mockBAKC;
    ApeCoinStaking internal mockApeStaking;
    DelegationRegistry internal mockDelegationRegistry;
    MockBNFTRegistry internal mockBNFTRegistry;
    MockBNFT internal mockBnftStBAYC;

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
        mockWETH = new MintableERC20("WETH", "WETH", 18);
        mockUSDT = new MintableERC20("USDT", "USDT", 6);
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

        // boundNFTs
        mockBNFTRegistry = new MockBNFTRegistry();
        mockBnftStBAYC = new MockBNFT("boundstBAYC", "boundstBAYC", address(stBAYC));
        mockBNFTRegistry.setBNFTContract(address(stBAYC), address(mockBnftStBAYC));

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
        uint256 totalCoinRewards = 10000000 * 1e18;
        mockApeCoin.mint(totalCoinRewards);
        mockApeCoin.transfer(address(mockApeStaking), totalCoinRewards);

        // changing the owner and admin
        vm.startPrank(coinPool.owner());
        coinPool.transferOwnership(poolOwner);
        nftPool.transferOwnership(poolOwner);
        stakeManager.transferOwnership(poolOwner);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        nftPool.setBNFTRegistry(address(mockBNFTRegistry));
        stakeManager.updateBotAdmin(botAdmin);
        vm.stopPrank();

        // update the block info
        vm.warp(1669748400);
        vm.roll(100);
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
}
