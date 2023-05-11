/* eslint-disable @typescript-eslint/ban-ts-comment */
import { task } from "hardhat/config";
import { BendCoinPool, BendNftPool, BendStakeManager, LendingMigrator } from "../typechain-types";
import {
  AAVE_ADDRESS_PROVIDER,
  APE_STAKING,
  BAKC,
  BAYC,
  BEND_ADDRESS_PROVIDER,
  BNFT_REGISTRY,
  DELEAGATE_CASH,
  FEE,
  FEE_RECIPIENT,
  getParams,
  MAYC,
} from "./config";
import {
  deployContract,
  deployImplementation,
  deployProxyContract,
  deployProxyContractWithoutInit,
  getContractAddressFromDB,
  getContractFromDB,
  getDeploySigner,
  waitForTx,
} from "./utils/helpers";
import { verifyEtherscanContract } from "./utils/verification";

task("deploy:full:StakedNFT", "Deploy all contracts for staked nfts").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await run("deploy:NftVault");
  await run("deploy:StBAYC");
  await run("deploy:StMAYC");
  await run("deploy:StBAKC");
});

task("deploy:NftVault", "Deploy NftVault").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  const apeStaking = getParams(APE_STAKING, network.name);
  const delegateCash = getParams(DELEAGATE_CASH, network.name);

  await deployContract("VaultLogic", [], true);
  const vaultLogic = await getContractAddressFromDB("VaultLogic");

  await deployProxyContract("NftVault", [apeStaking, delegateCash], true, undefined, { VaultLogic: vaultLogic });
});

task("deploy:StBAYC", "Deploy StBAYC").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  const bayc = getParams(BAYC, network.name);
  const nftVault = await getContractAddressFromDB("NftVault");

  await deployProxyContract("StBAYC", [bayc, nftVault], true);
});

task("deploy:StMAYC", "Deploy StMAYC").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  const mayc = getParams(MAYC, network.name);
  const nftVault = await getContractAddressFromDB("NftVault");

  await deployProxyContract("StMAYC", [mayc, nftVault], true);
});

task("deploy:StBAKC", "Deploy StBAKC").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  const bakc = getParams(BAKC, network.name);
  const nftVault = await getContractAddressFromDB("NftVault");

  await deployProxyContract("StBAKC", [bakc, nftVault], true);
});

task("deploy:full:staking", "Deploy all contracts for staking").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await run("deploy:BendCoinPool");
  await run("deploy:BendNftPool");
  await run("deploy:BendStakeManager");

  await run("deploy:config:BendCoinPool");
  await run("deploy:config:BendNftPool");
  await run("deploy:config:BendStakeManager");

  await run("deploy:BaycStrategy");
  await run("deploy:MaycStrategy");
  await run("deploy:BakcStrategy");
  await run("deploy:config:RewardsStrategy");

  await run("deploy:DefaultWithdrawStrategy");
  await run("deploy:config:WithdrawStrategy");
});

task("deploy:BendCoinPool", "Deploy BendCoinPool").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await deployProxyContractWithoutInit("BendCoinPool", [], true);
});

task("deploy:BendNftPool", "Deploy BendNftPool").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await deployProxyContractWithoutInit("BendNftPool", [], true);
});

task("deploy:BendStakeManager", "Deploy StakeManager").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await deployProxyContractWithoutInit("BendStakeManager", [], true);
});

task("deploy:BaycStrategy", "Deploy BaycStrategy").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await deployContract("BaycStrategy", [], true);
});

task("deploy:MaycStrategy", "Deploy MaycStrategy").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await deployContract("MaycStrategy", [], true);
});

task("deploy:BakcStrategy", "Deploy BakcStrategy").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await deployContract("BakcStrategy", [], true);
});

task("deploy:DefaultWithdrawStrategy", "Deploy DefaultWithdrawStrategy").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  const apeStaking = getParams(APE_STAKING, network.name);
  const nftVault = await getContractAddressFromDB("NftVault");
  const coinPool = await getContractAddressFromDB("BendCoinPool");
  const stakeManager = await getContractAddressFromDB("BendStakeManager");

  await deployContract("DefaultWithdrawStrategy", [apeStaking, nftVault, coinPool, stakeManager], true);
});

task("deploy:LendingMigrator", "Deploy LendingMigrator").setAction(async (_, { run }) => {
  await run("set-DRE");
  await run("compile");

  await deployProxyContractWithoutInit("LendingMigrator", [], true);
});

task("deploy:config:BendCoinPool", "Coinfig BendCoinPool").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");
  const deployer = await getDeploySigner();
  const coinPool = await getContractFromDB<BendCoinPool>("BendCoinPool");

  const apeStaking = getParams(APE_STAKING, network.name);
  const stakeManager = await getContractAddressFromDB("BendStakeManager");

  await waitForTx(await coinPool.connect(deployer).initialize(apeStaking, stakeManager));

  console.log("ok");
});

task("deploy:config:BendNftPool", "Coinfig BendNftPool").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");
  const deployer = await getDeploySigner();
  const nftPool = await getContractFromDB<BendNftPool>("BendNftPool");

  const apeStaking = getParams(APE_STAKING, network.name);
  const bnftRegistry = getParams(BNFT_REGISTRY, network.name);

  const coinPool = await getContractAddressFromDB("BendCoinPool");
  const stakeManager = await getContractAddressFromDB("BendStakeManager");

  const stBayc = await getContractAddressFromDB("StBAYC");
  const stMayc = await getContractAddressFromDB("StMAYC");
  const stBakc = await getContractAddressFromDB("StBAKC");

  await waitForTx(
    await nftPool.connect(deployer).initialize(bnftRegistry, apeStaking, coinPool, stakeManager, stBayc, stMayc, stBakc)
  );

  console.log("ok");
});

task("deploy:config:BendStakeManager", "Coinfig BendStakeManager").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");
  const deployer = await getDeploySigner();
  const stakeManager = await getContractFromDB<BendStakeManager>("BendStakeManager");

  const apeStaking = getParams(APE_STAKING, network.name);
  const coinPool = await getContractAddressFromDB("BendCoinPool");
  const nftPool = await getContractAddressFromDB("BendNftPool");
  const nftVault = await getContractAddressFromDB("NftVault");

  const stBayc = await getContractAddressFromDB("StBAYC");
  const stMayc = await getContractAddressFromDB("StMAYC");
  const stBakc = await getContractAddressFromDB("StBAKC");

  const fee = getParams(FEE, network.name);
  const feeRecipient = getParams(FEE_RECIPIENT, network.name);

  await waitForTx(
    await stakeManager.connect(deployer).initialize(apeStaking, coinPool, nftPool, nftVault, stBayc, stMayc, stBakc)
  );

  await waitForTx(await stakeManager.connect(deployer).updateFee(fee));
  await waitForTx(await stakeManager.connect(deployer).updateFeeRecipient(feeRecipient));

  console.log("ok");
});

task("deploy:config:RewardsStrategy", "Coinfig RewardsStrategy").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");
  const deployer = await getDeploySigner();
  const stakeManager = await getContractFromDB<BendStakeManager>("BendStakeManager");

  const bayc = getParams(BAYC, network.name);
  const mayc = getParams(MAYC, network.name);
  const bakc = getParams(BAKC, network.name);

  const baycStrategy = await getContractAddressFromDB("BaycStrategy");
  const maycStrategy = await getContractAddressFromDB("MaycStrategy");
  const bakcStrategy = await getContractAddressFromDB("BakcStrategy");

  await waitForTx(await stakeManager.connect(deployer).updateRewardsStrategy(bayc, baycStrategy));
  await waitForTx(await stakeManager.connect(deployer).updateRewardsStrategy(mayc, maycStrategy));
  await waitForTx(await stakeManager.connect(deployer).updateRewardsStrategy(bakc, bakcStrategy));

  console.log("ok");
});

task("deploy:config:WithdrawStrategy", "Coinfig WithdrawStrategy").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");
  const deployer = await getDeploySigner();
  const stakeManager = await getContractFromDB<BendStakeManager>("BendStakeManager");

  const bayc = getParams(BAYC, network.name);
  const mayc = getParams(MAYC, network.name);
  const bakc = getParams(BAKC, network.name);

  const withdrawStrategy = await getContractAddressFromDB("DefaultWithdrawStrategy");

  await waitForTx(await stakeManager.connect(deployer).updateWithdrawStrategy(withdrawStrategy));

  console.log("ok");
});

task("deploy:config:LendingMigrator", "Coinfig LendingMigrator").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");
  const deployer = await getDeploySigner();
  const migrator = await getContractFromDB<LendingMigrator>("LendingMigrator");

  const aaveProvider = getParams(AAVE_ADDRESS_PROVIDER, network.name);
  const bendProvider = getParams(BEND_ADDRESS_PROVIDER, network.name);

  const nftPool = await getContractAddressFromDB("BendNftPool");
  const stBayc = await getContractAddressFromDB("StBAYC");
  const stMayc = await getContractAddressFromDB("StMAYC");
  const stBakc = await getContractAddressFromDB("StBAKC");

  await waitForTx(
    await migrator.connect(deployer).initialize(aaveProvider, bendProvider, nftPool, stBayc, stMayc, stBakc)
  );

  console.log("ok");
});

task("deploy:NewImpl", "Deploy new implmentation")
  .addParam("implid", "The new impl contract id")
  .setAction(async ({ implid }, { run }) => {
    await run("set-DRE");
    await run("compile");

    await deployImplementation(implid, false);

    console.log("ok");
  });

task("prepareUpgrade", "Deploy new implmentation for upgrade")
  .addParam("proxyid", "The proxy contract id")
  .addParam("implid", "The new impl contract id")
  .setAction(async ({ proxyid, implid }, { ethers, upgrades, run }) => {
    await run("set-DRE");
    await run("compile");
    const proxyAddress = await getContractAddressFromDB(proxyid);
    const upgradeable = await ethers.getContractFactory(implid);
    console.log(`Preparing ${proxyid} upgrade at proxy ${proxyAddress}`);
    // @ts-ignore
    const implAddress = await upgrades.prepareUpgrade(proxyAddress, upgradeable);
    console.log("Implmentation at:", implAddress);
    const adminAddress = await upgrades.erc1967.getAdminAddress(proxyAddress);
    console.log("Proxy admin at:", adminAddress);
    await verifyEtherscanContract(implAddress.toString(), []);
  });

task("upgrade", "upgrade contract")
  .addParam("proxyid", "The proxy contract id")
  .addOptionalParam("implid", "The new impl contract id")
  .addOptionalParam("skipcheck", "Skip upgrade storage check or not")
  .setAction(async ({ skipcheck, proxyid, implid }, { ethers, upgrades, run }) => {
    await run("set-DRE");
    await run("compile");
    if (!implid) {
      implid = proxyid;
    }
    const proxyAddress = await getContractAddressFromDB(proxyid);
    const upgradeable = await ethers.getContractFactory(implid);
    console.log(`Preparing upgrade proxy ${proxyid}: ${proxyAddress} with new ${implid}`);
    // @ts-ignore
    const upgraded = await upgrades.upgradeProxy(proxyAddress, upgradeable, { unsafeSkipStorageCheck: !!skipcheck });
    await upgraded.deployed();
    const implAddress = await upgrades.erc1967.getImplementationAddress(upgraded.address);
    console.log("New implmentation at: ", implAddress);
    await verifyEtherscanContract(implAddress, []);
  });

task("forceImport", "force import implmentation to proxy")
  .addParam("proxy", "The proxy address")
  .addParam("implid", "The new impl contract id")
  .setAction(async ({ proxy, implid }, { ethers, upgrades, run }) => {
    await run("set-DRE");
    await run("compile");
    const upgradeable = await ethers.getContractFactory(implid);
    console.log(`Import proxy: ${proxy} with ${implid}`);
    // @ts-ignore
    await upgrades.forceImport(proxy, upgradeable);
  });

task("verify:Implementation", "verify implmentation")
  .addParam("impl", "The contract implementation address")
  .setAction(async ({ impl }, { ethers, upgrades, run }) => {
    await run("set-DRE");
    await run("compile");

    await verifyEtherscanContract(impl, []);
  });
