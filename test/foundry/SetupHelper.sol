pragma solidity 0.8.18;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";

import "../../contracts/test/MintableERC20.sol";
import "../../contracts/test/MintableERC721.sol";
import {ApeCoinStaking} from "../../contracts/test/ApeCoinStaking.sol";
import "../../contracts/test/DelegationRegistry.sol";
import "../../contracts/test/MockBNFTRegistry.sol";
import "../../contracts/test/MockBNFT.sol";
import {MockWAPE} from "../../contracts/test/MockWAPE.sol";
import {MockBeacon} from "../../contracts/test/MockBeacon.sol";

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

import {DefaultRewardsStrategy} from "../../contracts/strategy/DefaultRewardsStrategy.sol";
import {DefaultWithdrawStrategy} from "../../contracts/strategy/DefaultWithdrawStrategy.sol";

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
    MockWAPE internal mockWAPE;
    MintableERC20 internal mockWETH;
    MintableERC20 internal mockUSDT;
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

    struct PoolConfig {
        uint256 id;
        uint256 cap;
    }

    function setUp() public virtual {
        // prepare test users
        utilsHelper = new UtilitiesHelper();

        testUsers = utilsHelper.createUsers(5);
        testUser0 = testUsers[0];
        for (uint i = 0; i < testUsers.length; i++) {
            vm.deal(address(testUsers[i]), 10_000_000 ether);
        }

        adminOwners = utilsHelper.createUsers(5);
        poolOwner = adminOwners[0];
        botAdmin = adminOwners[1];
        feeRecipient = adminOwners[2];

        mockDelegationRegistry = new DelegationRegistry();

        // mocked ERC20 and NFTs
        mockWAPE = new MockWAPE(1069672766);

        mockWETH = new MintableERC20("WETH", "WETH", 18);
        mockUSDT = new MintableERC20("USDT", "USDT", 6);

        mockBAYC = new MintableERC721("Mock BAYC", "BAYC");
        mockMAYC = new MintableERC721("Mock MAYC", "MAYC");
        mockBAKC = new MintableERC721("Mock BAKC", "BAKC");

        // update the block info
        vm.warp(1669748400);
        vm.roll(100);

        // mocked ape staking and config params
        MockBeacon mockBeacon = new MockBeacon();
        mockApeStaking = new ApeCoinStaking(
            address(mockBeacon),
            address(mockBAYC),
            address(mockMAYC),
            address(mockBAKC)
        );
        PoolConfig[] memory poolConfigs = new PoolConfig[](4);
        poolConfigs[0] = PoolConfig({id: 0, cap: 0});
        poolConfigs[1] = PoolConfig({id: 1, cap: 10094000000000000000000});
        poolConfigs[2] = PoolConfig({id: 2, cap: 2042000000000000000000});
        poolConfigs[3] = PoolConfig({id: 3, cap: 856000000000000000000});
        for (uint i = 1; i < poolConfigs.length; i++) {
            uint256 startTime = (block.timestamp / 3600) * 3600;
            uint256 timeRane = 3600 * 24 * 90;
            uint256 poolAmount = 10500000000000000000000000 / (i + 1);

            for (uint j = 0; j < 4; j++) {
                uint256 endTime = startTime + timeRane;
                uint256 amount = poolAmount / (j + 1);

                mockApeStaking.addTimeRange{value: amount}(
                    poolConfigs[i].id,
                    amount,
                    startTime,
                    endTime,
                    poolConfigs[i].cap
                );

                startTime = endTime;
            }
        }

        // staked nfts
        nftVault = new NftVault();
        nftVault.initialize(
            address(mockWAPE),
            IApeCoinStaking(address(mockApeStaking)),
            IDelegationRegistry(mockDelegationRegistry)
        );
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

        coinPool.initialize(address(mockWAPE), IApeCoinStaking(address(mockApeStaking)), stakeManager);
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
        mockWAPE.approve(address(coinPool), initDeposit);
        coinPool.depositNativeSelf{value: initDeposit}();
        vm.stopPrank();
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
