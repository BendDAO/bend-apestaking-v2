pragma solidity 0.8.18;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";

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
import "../../contracts/interfaces/IWithdrawStrategy.sol";

import "../../contracts/stakednft/NftVault.sol";
import "../../contracts/stakednft/StBAYC.sol";
import "../../contracts/stakednft/StMAYC.sol";
import "../../contracts/stakednft/StBAKC.sol";

import "../../contracts/BendCoinPool.sol";
import "../../contracts/BendNftPool.sol";
import "../../contracts/BendStakeManager.sol";

import "../../contracts/strategy/DefaultRewardsStrategy.sol";
import "../../contracts/strategy/DefaultWithdrawStrategy.sol";

import "./UtilitiesHelper.sol";

abstract contract SetupHelper is Test {
    UtilitiesHelper internal utilsHelper;

    // mocked users
    address payable[] internal testUsers;
    address payable testUser0;
    address payable[] internal adminOwners;
    address payable poolOwner;
    address payable botAdmin;
    address payable feeRecipient;

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
    DefaultRewardsStrategy internal baycStrategy;
    DefaultRewardsStrategy internal maycStrategy;
    DefaultRewardsStrategy internal bakcStrategy;
    DefaultWithdrawStrategy internal withdrawStrategy;

    function setUp() public virtual {
        // prepare test users
        utilsHelper = new UtilitiesHelper();

        testUsers = utilsHelper.createUsers(5);
        testUser0 = testUsers[0];

        adminOwners = utilsHelper.createUsers(5);
        poolOwner = adminOwners[0];
        botAdmin = adminOwners[1];
        feeRecipient = adminOwners[2];

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
        nftVault = new NftVault();
        nftVault.initialize(IApeCoinStaking(address(mockApeStaking)), IDelegationRegistry(mockDelegationRegistry));
        stBAYC = new StBAYC();
        stBAYC.initialize(IERC721MetadataUpgradeable(address(mockBAYC)), nftVault);
        stMAYC = new StMAYC();
        stMAYC.initialize(IERC721MetadataUpgradeable(address(mockMAYC)), nftVault);
        stBAKC = new StBAKC();
        stBAKC.initialize(IERC721MetadataUpgradeable(address(mockBAKC)), nftVault);

        // boundNFTs
        mockBNFTRegistry = new MockBNFTRegistry();
        mockBnftStBAYC = new MockBNFT("boundstBAYC", "boundstBAYC", address(stBAYC));
        mockBNFTRegistry.setBNFTContract(address(stBAYC), address(mockBnftStBAYC));

        // staking contracts
        coinPool = new BendCoinPool();
        nftPool = new BendNftPool();
        stakeManager = new BendStakeManager();

        nftPool.initialize(
            mockBNFTRegistry,
            IApeCoinStaking(address(mockApeStaking)),
            coinPool,
            stakeManager,
            stBAYC,
            stMAYC,
            stBAKC
        );
        stakeManager.initialize(
            IApeCoinStaking(address(mockApeStaking)),
            coinPool,
            nftPool,
            nftVault,
            stBAYC,
            stMAYC,
            stBAKC
        );

        coinPool.initialize(IApeCoinStaking(address(mockApeStaking)), stakeManager);

        // set the strategy contracts
        baycStrategy = new DefaultRewardsStrategy(2400);
        maycStrategy = new DefaultRewardsStrategy(2700);
        bakcStrategy = new DefaultRewardsStrategy(2700);
        withdrawStrategy = new DefaultWithdrawStrategy(
            IApeCoinStaking(address(mockApeStaking)),
            nftVault,
            coinPool,
            stakeManager
        );
        stakeManager.updateRewardsStrategy(address(mockBAYC), IRewardsStrategy(baycStrategy));
        stakeManager.updateRewardsStrategy(address(mockMAYC), IRewardsStrategy(maycStrategy));
        stakeManager.updateRewardsStrategy(address(mockBAKC), IRewardsStrategy(bakcStrategy));
        stakeManager.updateWithdrawStrategy(IWithdrawStrategy(withdrawStrategy));

        // authorise
        stBAYC.authorise(address(stakeManager), true);
        stMAYC.authorise(address(stakeManager), true);
        stBAKC.authorise(address(stakeManager), true);

        nftVault.authorise(address(stakeManager), true);
        nftVault.authorise(address(stBAYC), true);
        nftVault.authorise(address(stMAYC), true);
        nftVault.authorise(address(stBAKC), true);

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
        stakeManager.updateBotAdmin(botAdmin);
        stakeManager.updateFee(400);
        stakeManager.updateFeeRecipient(feeRecipient);
        vm.stopPrank();

        uint256 initDeposit = 100 * 1e18;
        vm.startPrank(feeRecipient);
        mockApeCoin.mint(initDeposit);
        mockApeCoin.approve(address(coinPool), initDeposit);
        coinPool.deposit(initDeposit, feeRecipient);
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
