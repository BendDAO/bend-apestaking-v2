import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./_setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { makeBN18, mintNft, randomUint, skipHourBlocks } from "./utils";
import { BigNumber, constants } from "ethers";
import { advanceBlock, increaseBy } from "./helpers/block-traveller";

makeSuite("BendStakeManager", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let lastRevert: string;
  let baycTokenIds: number[];
  let maycTokenIds: number[];
  let bakcTokenIds: number[];
  const APE_COIN_AMOUNT = 70000;

  before(async () => {
    owner = env.accounts[1];

    baycTokenIds = [0, 1, 2, 3, 4, 5];
    await mintNft(owner, contracts.bayc, baycTokenIds);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);
    await contracts.bendNftPool.connect(owner).deposit(contracts.bayc.address, baycTokenIds);

    maycTokenIds = [6, 7, 8, 9, 10];
    await mintNft(owner, contracts.mayc, maycTokenIds);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);
    await contracts.bendNftPool.connect(owner).deposit(contracts.mayc.address, maycTokenIds);

    bakcTokenIds = [10, 11, 12, 13, 14];
    await mintNft(owner, contracts.bakc, bakcTokenIds);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);
    await contracts.bendNftPool.connect(owner).deposit(contracts.bakc.address, bakcTokenIds);

    await contracts.apeCoin.connect(owner).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.bendCoinPool.connect(owner).deposit(makeBN18(APE_COIN_AMOUNT), owner.address);

    lastRevert = "init";

    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  const advanceBlocks = async () => {
    await increaseBy(randomUint(3600, 3600 * 100));
    await advanceBlock();
    await skipHourBlocks(60);
  };

  it("prepareApeCoin: from pending ape coin only", async () => {
    const amount = makeBN18(randomUint(1, APE_COIN_AMOUNT - 1));
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();

    await expect(contracts.bendStakeManager.prepareApeCoin(amount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [constants.Zero.sub(amount), constants.Zero, amount]
    );
    expect(await contracts.bendCoinPool.pendingApeCoin()).eq(pendingApeCoin.sub(amount));
  });

  it("stakeApeCoin", async () => {
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(0);

    const amount = makeBN18(randomUint(1, APE_COIN_AMOUNT));
    // const amount = makeBN18(60000);
    // console.log(`stake ${amount.div(constants.WeiPerEther)}`);
    await expect(contracts.bendStakeManager.stakeApeCoin(amount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [constants.Zero.sub(amount), amount, constants.Zero]
    );

    expect(await contracts.bendCoinPool.pendingApeCoin()).eq(pendingApeCoin.sub(amount));
    expect(await contracts.bendStakeManager.stakedApeCoin(0)).eq(stakedAmount.add(amount));
    lastRevert = "stakeApeCoin";
    await snapshots.capture(lastRevert);
  });

  it("claimApeCoin", async () => {
    await advanceBlocks();
    const rewards = await contracts.bendStakeManager.pendingRewards(0);

    expect(await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0)).eq(rewards);

    await expect(contracts.bendStakeManager.claimApeCoin()).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(rewards), rewards]
    );

    expect(await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0))
      .eq(await contracts.bendStakeManager.pendingRewards(0))
      .eq(0);
  });

  it("unstakeApeCoin: unstake partiall", async () => {
    await advanceBlocks();
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    const unstakeAmount = (await contracts.bendStakeManager.stakedApeCoin(0)).div(2);

    expect(await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0)).eq(rewards);
    await expect(contracts.bendStakeManager.unstakeApeCoin(unstakeAmount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(unstakeAmount), unstakeAmount]
    );

    expect(await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0))
      .eq(await contracts.bendStakeManager.pendingRewards(0))
      .eq(rewards);
  });

  it("unstakeApeCoin: unstake fully", async () => {
    await advanceBlocks();
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(0);

    expect(await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0)).eq(rewards);

    await expect(contracts.bendStakeManager.unstakeApeCoin(unstakeAmount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(unstakeAmount).sub(rewards), unstakeAmount.add(rewards)]
    );

    expect(await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0))
      .eq(await contracts.bendStakeManager.pendingRewards(0))
      .eq(constants.Zero);
  });

  it("prepareApeCoin: from pending ape coin & rewards", async () => {
    await advanceBlocks();
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    const requiredAmount = pendingApeCoin.add(makeBN18(1));

    await expect(contracts.bendStakeManager.prepareApeCoin(requiredAmount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [rewards.sub(requiredAmount), constants.Zero.sub(rewards), requiredAmount]
    );
    expect(await contracts.bendCoinPool.pendingApeCoin()).eq(pendingApeCoin.add(rewards).sub(requiredAmount));
  });

  it("prepareApeCoin: from pending ape coin & rewards & staked", async () => {
    await advanceBlocks();
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();

    const requiredAmount = pendingApeCoin.add(rewards).add(makeBN18(1));

    await expect(contracts.bendStakeManager.prepareApeCoin(requiredAmount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [constants.Zero.sub(pendingApeCoin), constants.Zero.sub(rewards).sub(makeBN18(1)), requiredAmount]
    );
    expect(await contracts.bendCoinPool.pendingApeCoin()).eq(constants.Zero);
  });

  const calculateCoinPoolApeCoinDelta = (
    pendingApeCoin: BigNumber,
    pendingRewards: BigNumber,
    requiredAmount: BigNumber
  ) => {
    if (requiredAmount.lte(pendingApeCoin)) {
      console.log("pending ape coin only");
      return constants.Zero.sub(requiredAmount);
    }
    if (requiredAmount.gt(pendingApeCoin) && pendingRewards.gte(requiredAmount.sub(pendingApeCoin))) {
      console.log("pending ape coin & rewards");
      return pendingRewards.sub(requiredAmount);
    }
    console.log("pending ape coin & rewards & staked");
    return constants.Zero.sub(pendingApeCoin);
  };

  it("stakeBayc", async () => {
    await increaseBy(3600 * 10);
    await advanceBlock();
    await skipHourBlocks(60);
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    // console.log(`pending ape coin ${pendingApeCoin.div(constants.WeiPerEther)}`);
    const pendingRewards = await contracts.bendStakeManager.pendingRewards(0);
    // console.log(`rewards ${pendingRewards.div(constants.WeiPerEther)}`);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(1);
    const requiredAmount = makeBN18(10094 * baycTokenIds.length);
    // console.log(`required ${requiredAmount.div(constants.WeiPerEther)}`);
    const delta = calculateCoinPoolApeCoinDelta(pendingApeCoin, pendingRewards, requiredAmount);

    await expect(contracts.bendStakeManager.stakeBayc(baycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [delta, constants.Zero.sub(delta), constants.Zero]
    );

    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(stakedAmount.add(requiredAmount));
    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(
      await contracts.apeStaking.stakedTotal(contracts.nftVault.address)
    );
    lastRevert = "stakeBayc";
    await snapshots.capture(lastRevert);
  });
});
