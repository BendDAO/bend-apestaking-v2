pragma solidity 0.8.18;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "../contracts/test/MintableERC20.sol";
import "../contracts/test/MintableERC721.sol";
import "../contracts/test/ApeCoinStaking.sol";
import "../contracts/test/DelegationRegistry.sol";

import "../contracts/interfaces/IDelegationRegistry.sol";
import "../contracts/interfaces/IApeCoinStaking.sol";
import "../contracts/interfaces/IStakedNft.sol";
import "../contracts/interfaces/INftVault.sol";
import "../contracts/interfaces/ICoinPool.sol";
import "../contracts/interfaces/INftPool.sol";
import "../contracts/interfaces/IStakeManager.sol";

import "../contracts/stakednft/NftVault.sol";
import "../contracts/stakednft/StBAYC.sol";
import "../contracts/stakednft/StMAYC.sol";
import "../contracts/stakednft/stBAKC.sol";

import "../contracts/BendCoinPool.sol";
import "../contracts/BendNftPool.sol";
import "../contracts/BendStakeManager.sol";

import "./helpers/UtilitiesHelper.sol";

abstract contract SetupHelper is Test {
    UtilitiesHelper internal utilsHelper;
    address payable[] internal testUsers;
    address payable[] internal adminOwners;
    address payable botAdmin;

    MintableERC20 internal mockApeCoin;
    MintableERC721 internal mockBAYC;
    MintableERC721 internal mockMAYC;
    MintableERC721 internal mockBAKC;
    ApeCoinStaking internal mockApeStaking;
    DelegationRegistry internal mockDelegationRegistry;

    NftVault internal nftVault;
    StBAYC internal stBAYC;
    StMAYC internal stMAYC;
    StBAKC internal stBAKC;

    BendCoinPool internal coinPool;
    BendNftPool internal nftPool;
    BendStakeManager internal stakeManager;

    function setUp() public virtual {
        utilsHelper = new UtilitiesHelper();
        testUsers = utilsHelper.createUsers(5);
        adminOwners = utilsHelper.createUsers(5);

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
        nftPool.initialize(IDelegationRegistry(mockDelegationRegistry), coinPool, stakeManager, stBAYC, stMAYC, stBAKC);
        stakeManager.initialize(IApeCoinStaking(address(mockApeStaking)), coinPool, nftPool, nftVault);

        botAdmin = adminOwners[0];
        stakeManager.updateBot(botAdmin);

        // mint some coins
        uint256 totalCoinRewards = 1000000 * 10**18;
        mockApeCoin.mint(totalCoinRewards);
        mockApeCoin.transfer(address(mockApeStaking), totalCoinRewards);

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
