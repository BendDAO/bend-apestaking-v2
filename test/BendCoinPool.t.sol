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

contract BendCoinPoolTest is Test {
    MintableERC20 mockApeCoin;
    MintableERC721 mockBAYC;
    MintableERC721 mockMAYC;
    MintableERC721 mockBAKC;
    ApeCoinStaking mockApeStaking;
    DelegationRegistry mockDelegationRegistry;

    NftVault nftVault;
    StBAYC stBAYC;
    StMAYC stMAYC;
    StBAKC stBAKC;

    BendCoinPool coinPool;
    BendNftPool nftPool;
    BendStakeManager stakeManager;

    function setUp() public {
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
        stakeManager.initialize(IApeCoinStaking(address(mockApeStaking)), coinPool);

        // mint some coins
        uint256 totalCoinRewards = 1000000 * 10**18;
        mockApeCoin.mint(totalCoinRewards);
        mockApeCoin.transfer(address(mockApeStaking), totalCoinRewards);
    }

    function test_deposit() public {
        uint256 depositAmount = 1000000 * 10**18;
        mockApeCoin.mint(depositAmount);
        coinPool.deposit(depositAmount, address(this));
    }

    function testFail_deposit_NotEnoughBalance() public {
        coinPool.deposit(1000 * 10**18, address(this));
    }
}
