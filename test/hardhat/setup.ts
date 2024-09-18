/* eslint-disable @typescript-eslint/no-explicit-any */
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import {
  MintableERC721,
  MintableERC20,
  ApeCoinStaking,
  BendStakeManagerTester,
  IDelegationRegistry,
  IRewardsStrategy,
  MockBNFTRegistry,
  MockBNFT,
  MockAaveLendPoolAddressesProvider,
  MockAaveLendPool,
  MockBendLendPoolAddressesProvider,
  MockBendLendPool,
  MockBendLendPoolLoan,
  LendingMigrator,
  NftVault,
  StBAKC,
  StMAYC,
  StBAYC,
  DefaultWithdrawStrategy,
  IWithdrawStrategy,
  BendCoinPool,
  BendNftPool,
  MockBendApeCoinV1,
  MockStakeManagerV1,
  CompoudV1Migrator,
  PoolViewer,
  BendApeCoinStakedVoting,
  MockDelegationRegistryV2,
  MockAddressProviderV2,
} from "../../typechain-types";
import { Contract, BigNumber, constants } from "ethers";
import { parseEther } from "ethers/lib/utils";
import { advanceHours, deployContract } from "./utils";
import { latest } from "./helpers/block-traveller";
import { forEach } from "lodash";

export interface Env {
  initialized: boolean;
  fee: number;
  accounts: SignerWithAddress[];
  admin: SignerWithAddress;
  feeRecipient: SignerWithAddress;
  chainId: number;
}

export interface Contracts {
  initialized: boolean;
  delegateCash: IDelegationRegistry;

  // nft
  bayc: MintableERC721;
  mayc: MintableERC721;
  bakc: MintableERC721;
  // ape staking
  apeCoin: MintableERC20;
  apeStaking: ApeCoinStaking;
  // staked nft
  nftVault: NftVault;
  stBayc: StBAYC;
  stMayc: StMAYC;
  stBakc: StBAKC;
  // bound nft
  bnftRegistry: MockBNFTRegistry;
  bnftStBayc: MockBNFT;
  bnftStMayc: MockBNFT;
  bnftStBakc: MockBNFT;
  // bend ape staking v2
  bendStakeManager: BendStakeManagerTester;
  bendCoinPool: BendCoinPool;
  bendNftPool: BendNftPool;
  baycStrategy: IRewardsStrategy;
  maycStrategy: IRewardsStrategy;
  bakcStrategy: IRewardsStrategy;
  withdrawStrategy: DefaultWithdrawStrategy;
  // lending pool
  weth: MintableERC20;
  usdt: MintableERC20;
  mockAaveLendPoolAddressesProvider: MockAaveLendPoolAddressesProvider;
  mockAaveLendPool: MockAaveLendPool;
  mockBendLendPoolAddressesProvider: MockBendLendPoolAddressesProvider;
  mockBendLendPool: MockBendLendPool;
  mockBendLendPoolLoan: MockBendLendPoolLoan;
  lendingMigrator: LendingMigrator;
  // v1 staking
  mockCoinPoolV1: MockBendApeCoinV1;
  mockStakeManagerV1: MockStakeManagerV1;
  compoudV1Migrator: CompoudV1Migrator;
  // v2 lending
  mockAddressProviderV2: MockAddressProviderV2;
  poolViewer: PoolViewer;
  // voting
  stakedVoting: BendApeCoinStakedVoting;
  // delegate
  mockDelegationRegistryV2: MockDelegationRegistryV2;
}

export async function setupEnv(env: Env, contracts: Contracts): Promise<void> {
  env.fee = 100;
  env.accounts = (await ethers.getSigners()).slice(0, 6);
  env.admin = env.accounts[0];
  env.feeRecipient = env.accounts[2];
  env.chainId = (await ethers.provider.getNetwork()).chainId;

  for (const user of env.accounts) {
    // Each user gets 100K ape coin
    await contracts.apeCoin.connect(user).mint(parseEther("100000"));
  }
  await contracts.apeCoin.connect(env.admin).mint(parseEther("100000000"));
  await contracts.apeCoin.connect(env.admin).transfer(contracts.apeStaking.address, parseEther("100000000"));

  // ApeCoin pool
  const latestBlockTime = await latest();
  const poolConfigs: {
    id: number;
    cap: BigNumber;
  }[] = [];
  poolConfigs.push({
    id: 0,
    cap: BigNumber.from("0"),
  });
  poolConfigs.push({
    id: 1,
    cap: BigNumber.from("10094000000000000000000"),
  });
  poolConfigs.push({
    id: 2,
    cap: BigNumber.from("2042000000000000000000"),
  });
  poolConfigs.push({
    id: 3,
    cap: BigNumber.from("856000000000000000000"),
  });

  for (const poolConfig of poolConfigs) {
    let startTime = latestBlockTime - 3600 * 24 * 30;
    startTime = Math.floor(startTime / 3600) * 3600;
    let timeRage = 3600 * 24 * 90;
    let poolAmount = BigNumber.from("10500000000000000000000000").div(poolConfig.id + 1);

    for (let timeIdx = 0; timeIdx < 4; timeIdx++) {
      let endTime = startTime + timeRage;
      const amount = poolAmount.div(timeIdx + 1);

      await contracts.apeStaking.addTimeRange(poolConfig.id, amount, startTime, endTime, poolConfig.cap);

      startTime = endTime;
    }
  }

  // bend staking
  await contracts.mockAaveLendPoolAddressesProvider.setLendingPool(contracts.mockAaveLendPool.address);

  await contracts.mockBendLendPoolAddressesProvider.setLendPool(contracts.mockBendLendPool.address);
  await contracts.mockBendLendPoolAddressesProvider.setLendPoolLoan(contracts.mockBendLendPoolLoan.address);
  await contracts.mockBendLendPool.setAddressesProvider(contracts.mockBendLendPoolAddressesProvider.address);

  await (contracts.bendStakeManager as Contract).initialize(
    contracts.apeStaking.address,
    contracts.bendCoinPool.address,
    contracts.bendNftPool.address,
    contracts.nftVault.address,
    contracts.stBayc.address,
    contracts.stMayc.address,
    contracts.stBakc.address
  );

  await (contracts.bendNftPool as Contract).initialize(
    contracts.bnftRegistry.address,
    contracts.apeStaking.address,
    contracts.bendCoinPool.address,
    contracts.bendStakeManager.address,
    contracts.stBayc.address,
    contracts.stMayc.address,
    contracts.stBakc.address
  );

  await contracts.apeCoin.connect(env.admin).approve(contracts.bendCoinPool.address, constants.MaxUint256);
  await (contracts.bendCoinPool as Contract).initialize(
    contracts.apeStaking.address,
    contracts.bendStakeManager.address
  );

  await contracts.lendingMigrator.initialize(
    contracts.mockAaveLendPoolAddressesProvider.address,
    contracts.mockBendLendPoolAddressesProvider.address,
    contracts.bendNftPool.address,
    contracts.stBayc.address,
    contracts.stMayc.address,
    contracts.stBakc.address
  );

  await contracts.bendStakeManager.updateRewardsStrategy(contracts.bayc.address, contracts.baycStrategy.address);
  await contracts.bendStakeManager.updateRewardsStrategy(contracts.mayc.address, contracts.maycStrategy.address);
  await contracts.bendStakeManager.updateRewardsStrategy(contracts.bakc.address, contracts.bakcStrategy.address);
  await contracts.bendStakeManager.updateWithdrawStrategy(contracts.withdrawStrategy.address);

  await contracts.bendStakeManager.updateFee(400);
  await contracts.bendStakeManager.updateFeeRecipient(env.feeRecipient.address);

  await contracts.bnftRegistry.setBNFTContract(contracts.stBayc.address, contracts.bnftStBayc.address);
  await contracts.bnftRegistry.setBNFTContract(contracts.stMayc.address, contracts.bnftStMayc.address);
  await contracts.bnftRegistry.setBNFTContract(contracts.stBakc.address, contracts.bnftStBakc.address);

  await contracts.stBayc.setBnftRegistry(contracts.bnftRegistry.address);
  await contracts.stMayc.setBnftRegistry(contracts.bnftRegistry.address);
  await contracts.stBakc.setBnftRegistry(contracts.bnftRegistry.address);

  await contracts.stBayc.authorise(contracts.bendStakeManager.address, true);
  await contracts.stMayc.authorise(contracts.bendStakeManager.address, true);
  await contracts.stBakc.authorise(contracts.bendStakeManager.address, true);

  await contracts.nftVault.authorise(contracts.stBayc.address, true);
  await contracts.nftVault.authorise(contracts.stMayc.address, true);
  await contracts.nftVault.authorise(contracts.stBakc.address, true);
  await contracts.nftVault.authorise(contracts.bendStakeManager.address, true);

  await contracts.nftVault.setDelegationRegistryV2Contract(contracts.mockDelegationRegistryV2.address);

  await contracts.compoudV1Migrator.initialize(
    contracts.apeCoin.address,
    contracts.mockStakeManagerV1.address,
    contracts.mockCoinPoolV1.address,
    contracts.bendCoinPool.address
  );

  await contracts.bendNftPool.setV2AddressProvider(contracts.mockAddressProviderV2.address);
}

export async function setupContracts(): Promise<Contracts> {
  const delegateCash = await deployContract<IDelegationRegistry>("DelegationRegistry", []);
  // nft
  const bayc = await deployContract<MintableERC721>("MintableERC721", ["BAYC", "BAYC"]);
  const mayc = await deployContract<MintableERC721>("MintableERC721", ["MAYC", "MAYC"]);
  const bakc = await deployContract<MintableERC721>("MintableERC721", ["BAKC", "BAKC"]);

  // ape staking
  const apeCoin = await deployContract<MintableERC20>("MintableERC20", ["ApeCoin", "ApeCoin", 18]);
  const apeStaking = await deployContract<ApeCoinStaking>("ApeCoinStaking", [
    apeCoin.address,
    bayc.address,
    mayc.address,
    bakc.address,
  ]);

  //  staked nft
  const vaultLogic = await deployContract("VaultLogic", []);
  const nftVault = await deployContract<NftVault>("NftVault", [], { VaultLogic: vaultLogic.address });
  await nftVault.initialize(apeStaking.address, delegateCash.address);
  const stBayc = await deployContract<StBAYC>("StBAYC", []);
  await stBayc.initialize(bayc.address, nftVault.address);
  const stMayc = await deployContract<StMAYC>("StMAYC", []);
  await stMayc.initialize(mayc.address, nftVault.address);
  const stBakc = await deployContract<StBAKC>("StBAKC", []);
  await stBakc.initialize(bakc.address, nftVault.address);

  // bound nft
  const bnftRegistry = await deployContract<MockBNFTRegistry>("MockBNFTRegistry", []);
  const bnftStBayc = await deployContract<MockBNFT>("MockBNFT", ["bnftStBayc", "bnftStBayc", stBayc.address]);
  const bnftStMayc = await deployContract<MockBNFT>("MockBNFT", ["bnftStMayc", "bnftStMayc", stBayc.address]);
  const bnftStBakc = await deployContract<MockBNFT>("MockBNFT", ["bnftStBakc", "bnftStBakc", stBayc.address]);

  // bend staking v2
  const bendStakeManager = await deployContract<BendStakeManagerTester>("BendStakeManagerTester", []);
  const bendCoinPool = await deployContract<BendCoinPool>("BendCoinPool", []);
  const bendNftPool = await deployContract<BendNftPool>("BendNftPool", []);

  const baycStrategy = await deployContract<IRewardsStrategy>("DefaultRewardsStrategy", [2400]);
  const maycStrategy = await deployContract<IRewardsStrategy>("DefaultRewardsStrategy", [2700]);
  const bakcStrategy = await deployContract<IRewardsStrategy>("DefaultRewardsStrategy", [2700]);

  const withdrawStrategy = await deployContract<IWithdrawStrategy>("DefaultWithdrawStrategy", [
    apeStaking.address,
    nftVault.address,
    bendCoinPool.address,
    bendStakeManager.address,
  ]);

  // lending pool
  const weth = await deployContract<MintableERC20>("MintableERC20", ["WETH", "WETH", 18]);
  const usdt = await deployContract<MintableERC20>("MintableERC20", ["USDT", "USDT", 6]);

  const mockAaveLendPoolAddressesProvider = await deployContract<MockAaveLendPoolAddressesProvider>(
    "MockAaveLendPoolAddressesProvider",
    []
  );
  const mockAaveLendPool = await deployContract<MockAaveLendPool>("MockAaveLendPool", []);
  const mockBendLendPoolAddressesProvider = await deployContract<MockBendLendPoolAddressesProvider>(
    "MockBendLendPoolAddressesProvider",
    []
  );
  const mockBendLendPool = await deployContract<MockBendLendPool>("MockBendLendPool", []);
  const mockBendLendPoolLoan = await deployContract<MockBendLendPoolLoan>("MockBendLendPoolLoan", []);
  const lendingMigrator = await deployContract<LendingMigrator>("LendingMigrator", []);

  // v1 staking
  const mockCoinPoolV1 = await deployContract<MockBendApeCoinV1>("MockBendApeCoinV1", [apeCoin.address]);
  const mockStakeManagerV1 = await deployContract<MockStakeManagerV1>("MockStakeManagerV1", [apeCoin.address]);
  const compoudV1Migrator = await deployContract<CompoudV1Migrator>("CompoudV1Migrator", []);

  // v2 lending
  const mockAddressProviderV2 = await deployContract<MockAddressProviderV2>("MockAddressProviderV2", []);

  const poolViewer = await deployContract<PoolViewer>("PoolViewer", [
    apeStaking.address,
    bendCoinPool.address,
    bendStakeManager.address,
    bnftRegistry.address,
    mockAddressProviderV2.address,
  ]);

  // voting
  const stakedVoting = await deployContract<BendApeCoinStakedVoting>("BendApeCoinStakedVoting", [
    bendCoinPool.address,
    bendNftPool.address,
    bendStakeManager.address,
    bnftRegistry.address,
  ]);

  // delegate registry v2
  const mockDelegationRegistryV2 = await deployContract<MockDelegationRegistryV2>("MockDelegationRegistryV2", []);

  return {
    initialized: true,
    delegateCash,
    bayc,
    mayc,
    bakc,
    apeCoin,
    apeStaking,
    nftVault,
    stBayc,
    stMayc,
    stBakc,
    bnftRegistry,
    bnftStBayc,
    bnftStMayc,
    bnftStBakc,
    bendStakeManager,
    bendCoinPool,
    bendNftPool,
    baycStrategy,
    maycStrategy,
    bakcStrategy,
    withdrawStrategy,
    weth,
    usdt,
    mockAaveLendPoolAddressesProvider,
    mockAaveLendPool,
    mockBendLendPoolAddressesProvider,
    mockBendLendPool,
    mockBendLendPoolLoan,
    lendingMigrator,
    mockCoinPoolV1,
    mockStakeManagerV1,
    compoudV1Migrator,
    mockAddressProviderV2,
    poolViewer,
    stakedVoting,
    mockDelegationRegistryV2,
  } as Contracts;
}

export class Snapshots {
  ids = new Map<string, string>();

  async capture(tag: string): Promise<void> {
    this.ids.set(tag, await this.evmSnapshot());
  }

  async revert(tag: string): Promise<void> {
    await this.evmRevert(this.ids.get(tag) || "1");
    await this.capture(tag);
  }

  async evmSnapshot(): Promise<any> {
    return await ethers.provider.send("evm_snapshot", []);
  }

  async evmRevert(id: string): Promise<any> {
    return await ethers.provider.send("evm_revert", [id]);
  }
}

const contracts: Contracts = { initialized: false } as Contracts;
const env: Env = { initialized: false } as Env;
const snapshots = new Snapshots();
export function makeSuite(name: string, tests: (contracts: Contracts, env: Env, snapshots: Snapshots) => void): void {
  describe(name, () => {
    let _id: any;
    before(async () => {
      if (!env.initialized && !contracts.initialized) {
        Object.assign(contracts, await setupContracts());
        await setupEnv(env, contracts);
        env.initialized = true;
        contracts.initialized = true;
        snapshots.capture("setup");
      }
      _id = await snapshots.evmSnapshot();
    });
    tests(contracts, env, snapshots);
    after(async () => {
      await snapshots.evmRevert(_id);
    });
  });
}
