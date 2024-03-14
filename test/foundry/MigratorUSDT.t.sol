// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../contracts/misc/LendingMigrator.sol";

contract TestMigratorUSDT is Test {
    using SafeERC20 for IERC20;

    // the address of the contract on the mainnet fork
    address constant multisigOwnerAddress = 0xe6b80f77a8B8FcD124aB748C720B7EAEA83dDb4C;
    address constant timelockController7DAddress = 0x4e4C314E2391A58775be6a15d7A05419ba7D2B6e;
    address constant proxyAdminAddress = 0xcfCF3A49552EC920497EE0DEbC965C31044D0118;

    address constant migratorAddress = 0x968c9090a217786f414025ceF11540f801f38ee1;
    address constant userAddress = 0x8F45D77F7c0D8e4023eAb2A2e36C83667c6B0253;
    address constant nftAddress = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    // contracts
    ProxyAdmin public proxyAdmin;
    LendingMigrator public migrator;

    // how to run this testcase
    // url: https://eth-mainnet.g.alchemy.com/v2/xxx
    // forge test --match-contract TestMigratorUSDT --fork-url https://RPC --fork-block-number 19425293

    function setUp() public {
        proxyAdmin = ProxyAdmin(proxyAdminAddress);
        migrator = LendingMigrator(migratorAddress);
    }

    function testMigrate() public {
        // upgrade contract
        LendingMigrator migratorImpl = new LendingMigrator();

        vm.prank(timelockController7DAddress);
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(migratorAddress), address(migratorImpl));

        // try migrate
        address[] memory nftAssets = new address[](1);
        nftAssets[0] = nftAddress;
        uint256[] memory nftTokenIds = new uint256[](1);
        nftTokenIds[0] = 6890;

        vm.prank(userAddress);
        migrator.migrate(nftAssets, nftTokenIds);
    }
}
