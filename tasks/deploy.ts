/* eslint-disable @typescript-eslint/ban-ts-comment */
import { task } from "hardhat/config";
import { utils } from "ethers";
import { BendCoinPool, BendNftPool, BendStakeManager } from "../typechain-types";
import { APE_STAKING, BAKC, BAYC, DELEAGATE_CASH, FEE, FEE_RECIPIENT, getParams, MAYC } from "./config";
import {
  deployContract,
  deployProxyContractWithoutInit,
  getContractAddressFromDB,
  getContractFromDB,
  getDeploySigner,
  waitForTx,
} from "./utils/helpers";
import { verifyEtherscanContract } from "./utils/verification";

task("deploy:full:stnft", "Deploy all contracts for staked nfts").setAction(async (_, { run }) => {
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

  await deployContract("NftVault", [apeStaking, delegateCash], false);
});

task("deploy:StBAYC", "Deploy StBAYC").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  const bayc = getParams(BAYC, network.name);
  const nftVault = await getContractAddressFromDB("NftVault");

  await deployContract("StBAYC", [bayc, nftVault], false);
});

task("deploy:StMAYC", "Deploy StMAYC").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  const mayc = getParams(MAYC, network.name);
  const nftVault = await getContractAddressFromDB("NftVault");

  await deployContract("StMAYC", [mayc, nftVault], false);
});

task("deploy:StBAKC", "Deploy StBAKC").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  const bakc = getParams(BAKC, network.name);
  const nftVault = await getContractAddressFromDB("NftVault");

  await deployContract("StBAKC", [bakc, nftVault], false);
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
});

task("deploy:BendCoinPool", "Deploy BendCoinPool").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  await deployProxyContractWithoutInit("BendCoinPool", [], false);
});

task("deploy:BendNftPool", "Deploy BendNftPool").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  await deployProxyContractWithoutInit("BendNftPool", [], false);
});

task("deploy:BendStakeManager", "Deploy StakeManager").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");

  await deployProxyContractWithoutInit("BendStakeManager", [], false);
});

task("deploy:config:BendCoinPool", "Coinfig BendCoinPool").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");
  const deployer = await getDeploySigner();
  const coinPool = await getContractFromDB<BendCoinPool>("BendCoinPool");

  const apeStaking = getParams(APE_STAKING, network.name);
  const stakeManager = await getContractAddressFromDB("BendStakeManager");

  await waitForTx(await coinPool.connect(deployer).initialize(apeStaking, stakeManager));
});

task("deploy:config:BendNftPool", "Coinfig BendNftPool").setAction(async (_, { network, run }) => {
  await run("set-DRE");
  await run("compile");
  const deployer = await getDeploySigner();
  const nftPool = await getContractFromDB<BendNftPool>("BendNftPool");

  const apeStaking = getParams(APE_STAKING, network.name);
  const delegationCash = getParams(DELEAGATE_CASH, network.name);

  const coinPool = await getContractAddressFromDB("BendCoinPool");
  const stakeManager = await getContractAddressFromDB("BendStakeManager");

  const stBayc = await getContractAddressFromDB("StBAYC");
  const stMayc = await getContractAddressFromDB("StMAYC");
  const stBakc = await getContractAddressFromDB("StBAKC");

  await waitForTx(
    await nftPool
      .connect(deployer)
      .initialize(apeStaking, delegationCash, coinPool, stakeManager, stBayc, stMayc, stBakc)
  );
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

  const fee = getParams(FEE, network.name);
  const feeRecipient = getParams(FEE_RECIPIENT, network.name);

  await waitForTx(await stakeManager.connect(deployer).initialize(apeStaking, coinPool, nftPool, nftVault));

  await waitForTx(await stakeManager.connect(deployer).updateFee(fee));
  await waitForTx(await stakeManager.connect(deployer).updateFeeRecipient(feeRecipient));
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
