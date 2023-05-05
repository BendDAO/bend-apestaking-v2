import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./_setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { makeBN18, mintNft, randomUint, shuffledSubarray, skipHourBlocks } from "./utils";
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

  const advanceHours = async (hours: number) => {
    await increaseBy(randomUint(3600, 3600 * hours));
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
    await advanceHours(10);
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

  it("unstakeApeCoin: unstake partially", async () => {
    await advanceHours(10);
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
    await advanceHours(10);
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
    await advanceHours(10);
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
    await advanceHours(10);
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

  const calculateCoinPoolApeCoinDelta = async (requiredAmount: BigNumber) => {
    // console.log(`required ${requiredAmount.div(constants.WeiPerEther)}`);
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    // console.log(`pending ape coin ${pendingApeCoin.div(constants.WeiPerEther)}`);
    const pendingRewards = await contracts.bendStakeManager.pendingRewards(0);
    // console.log(`rewards ${pendingRewards.div(constants.WeiPerEther)}`);
    if (requiredAmount.lte(pendingApeCoin)) {
      // console.log("pending ape coin only");
      return constants.Zero.sub(requiredAmount);
    }
    if (requiredAmount.gt(pendingApeCoin) && pendingRewards.gte(requiredAmount.sub(pendingApeCoin))) {
      // console.log("pending ape coin & rewards");
      return pendingRewards.sub(requiredAmount);
    }
    // console.log("pending ape coin & rewards & staked");
    return constants.Zero.sub(pendingApeCoin);
  };

  it("stakeBayc", async () => {
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(1);
    const requiredAmount = makeBN18(10094 * baycTokenIds.length);
    const delta = await calculateCoinPoolApeCoinDelta(requiredAmount);

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

  it("claimBayc", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(1);
    let expectRewards = constants.Zero;

    for (const id of baycTokenIds) {
      expectRewards = expectRewards.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
    }
    expect(rewards).eq(expectRewards);

    await expect(contracts.bendStakeManager.claimBayc(baycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(rewards), rewards]
    );

    for (const id of baycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(0);
  });

  it("unstakeBayc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(1);
    const baycPoolRewards = await contracts.baycStrategy.calculateNftRewards(rewards);
    // const coinPoolRewards = rewards.sub(baycPoolRewards);
    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(1);

    const preCoinshares = await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address);
    await expect(contracts.bendStakeManager.unstakeBayc(baycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [constants.Zero.sub(unstakeAmount).sub(rewards), unstakeAmount.add(rewards), constants.Zero]
    );
    const sharesDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preCoinshares);
    expect(await contracts.bendCoinPool.convertToAssets(sharesDelta)).closeTo(baycPoolRewards, 10); // round down

    for (const id of baycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(0);
  });

  it("unstakeBayc: unstake partially", async () => {
    await advanceHours(10);
    let rewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let pendingRewards = constants.Zero;
    const unstakeBaycTokenId = [];
    for (const [i, id] of baycTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeBaycTokenId.push(id);
        rewards = rewards.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
      } else {
        pendingRewards = pendingRewards.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
      }
    }
    const baycPoolRewards = await contracts.baycStrategy.calculateNftRewards(rewards);
    const preCoinshares = await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address);
    await expect(contracts.bendStakeManager.unstakeBayc(unstakeBaycTokenId)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [constants.Zero.sub(unstakeAmount).sub(rewards), unstakeAmount.add(rewards), constants.Zero]
    );
    const sharesDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preCoinshares);
    expect(await contracts.bendCoinPool.convertToAssets(sharesDelta)).closeTo(baycPoolRewards, 10);

    for (const id of unstakeBaycTokenId) {
      expect(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(pendingRewards);
    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(stakeAmount);
  });

  it("stakeMayc", async () => {
    // await snapshots.revert("stakeApeCoin");
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(2);
    const requiredAmount = makeBN18(2042 * maycTokenIds.length);
    const delta = await calculateCoinPoolApeCoinDelta(requiredAmount);
    const preStakedTotal = await contracts.apeStaking.stakedTotal(contracts.nftVault.address);

    await expect(contracts.bendStakeManager.stakeMayc(maycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [delta, constants.Zero.sub(delta), constants.Zero]
    );

    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(stakedAmount.add(requiredAmount));

    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(
      (await contracts.apeStaking.stakedTotal(contracts.nftVault.address)).sub(preStakedTotal)
    );

    lastRevert = "stakeMayc";
    await snapshots.capture(lastRevert);
  });

  it("claimMayc", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(2);
    let expectRewards = constants.Zero;

    for (const id of maycTokenIds) {
      expectRewards = expectRewards.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
    }
    expect(rewards).eq(expectRewards);

    await expect(contracts.bendStakeManager.claimMayc(maycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(rewards), rewards]
    );

    for (const id of maycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(0);
  });

  it("unstakeMayc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(2);
    const maycPoolRewards = await contracts.maycStrategy.calculateNftRewards(rewards);
    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(2);

    const preCoinshares = await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address);

    await expect(contracts.bendStakeManager.unstakeMayc(maycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [constants.Zero.sub(unstakeAmount).sub(rewards), unstakeAmount.add(rewards), constants.Zero]
    );

    const sharesDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preCoinshares);
    expect(await contracts.bendCoinPool.convertToAssets(sharesDelta)).closeTo(maycPoolRewards, 10);

    for (const id of maycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(0);
  });

  it("unstakeMayc: unstake partially", async () => {
    await advanceHours(10);
    let rewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let pendingRewards = constants.Zero;
    const unstakeMaycTokenId = [];
    for (const [i, id] of maycTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeMaycTokenId.push(id);
        rewards = rewards.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
      } else {
        pendingRewards = pendingRewards.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
      }
    }
    const maycPoolRewards = await contracts.maycStrategy.calculateNftRewards(rewards);
    const preCoinshares = await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address);
    await expect(contracts.bendStakeManager.unstakeMayc(unstakeMaycTokenId)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [constants.Zero.sub(unstakeAmount).sub(rewards), unstakeAmount.add(rewards), constants.Zero]
    );

    const sharesDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preCoinshares);
    expect(await contracts.bendCoinPool.convertToAssets(sharesDelta)).closeTo(maycPoolRewards, 10);

    for (const id of unstakeMaycTokenId) {
      expect(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(pendingRewards);
    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(stakeAmount);
  });

  it("stakeBakc", async () => {
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(3);
    const requiredAmount = makeBN18(856 * maycTokenIds.length);
    const delta = await calculateCoinPoolApeCoinDelta(requiredAmount);
    const preStakedTotal = await contracts.apeStaking.stakedTotal(contracts.nftVault.address);

    let baycNfts = [];
    let maycNfts = [];
    for (let [i, id] of bakcTokenIds.entries()) {
      if (i % 2 === 1) {
        baycNfts.push({
          mainTokenId: baycTokenIds[baycNfts.length],
          bakcTokenId: id,
        });
      } else {
        maycNfts.push({
          mainTokenId: maycTokenIds[maycNfts.length],
          bakcTokenId: id,
        });
      }
    }

    await expect(contracts.bendStakeManager.stakeBakc(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [delta, constants.Zero.sub(delta), constants.Zero]
    );

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(stakedAmount.add(requiredAmount));

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(
      (await contracts.apeStaking.stakedTotal(contracts.nftVault.address)).sub(preStakedTotal)
    );

    lastRevert = "stakeBakc";
    await snapshots.capture(lastRevert);
  });

  it("claimBakc", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(3);
    let expectRewards = constants.Zero;

    for (const id of bakcTokenIds) {
      expectRewards = expectRewards.add(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id));
    }
    expect(rewards).eq(expectRewards);

    const bakcPoolRewards = await contracts.bakcStrategy.calculateNftRewards(rewards);

    let baycNfts = [];
    let maycNfts = [];
    for (let id of bakcTokenIds) {
      const pairStauts = await contracts.apeStaking.bakcToMain(id, 1);
      if (pairStauts.isPaired) {
        baycNfts.push({
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
        });
      } else {
        const pairStauts = await contracts.apeStaking.bakcToMain(id, 2);
        maycNfts.push({
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
        });
      }
    }

    const preCoinshares = await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address);

    await expect(contracts.bendStakeManager.claimBakc(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(rewards), rewards]
    );
    const sharesDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preCoinshares);
    expect(await contracts.bendCoinPool.convertToAssets(sharesDelta)).closeTo(bakcPoolRewards, 10);

    for (const id of bakcTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(0);
  });

  it("unstakeBakc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(3);
    const bakcPoolRewards = await contracts.bakcStrategy.calculateNftRewards(rewards);
    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(3);

    let baycNfts = [];
    let maycNfts = [];
    for (let id of bakcTokenIds) {
      const pairStauts = await contracts.apeStaking.bakcToMain(id, 1);
      if (pairStauts.isPaired) {
        baycNfts.push({
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
        });
      } else {
        const pairStauts = await contracts.apeStaking.bakcToMain(id, 2);
        maycNfts.push({
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
        });
      }
    }

    const preCoinshares = await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address);
    await expect(contracts.bendStakeManager.unstakeBakc(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [constants.Zero.sub(unstakeAmount).sub(rewards), unstakeAmount.add(rewards), constants.Zero]
    );
    const sharesDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preCoinshares);
    expect(await contracts.bendCoinPool.convertToAssets(sharesDelta)).closeTo(bakcPoolRewards, 10);
    for (const id of bakcTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(0);
  });

  it("unstakBakc: unstake partially", async () => {
    await advanceHours(10);
    let rewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let pendingRewards = constants.Zero;
    const unstakeBakcTokenId = [];

    for (const [i, id] of bakcTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeBakcTokenId.push(id);
        rewards = rewards.add(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(3, id)).stakedAmount);
      } else {
        pendingRewards = pendingRewards.add(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id));
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(3, id)).stakedAmount);
      }
    }
    const bakcPoolRewards = await contracts.bakcStrategy.calculateNftRewards(rewards);

    let baycNfts = [];
    let maycNfts = [];
    for (let id of unstakeBakcTokenId) {
      const pairStauts = await contracts.apeStaking.bakcToMain(id, 1);
      if (pairStauts.isPaired) {
        baycNfts.push({
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
        });
      } else {
        const pairStauts = await contracts.apeStaking.bakcToMain(id, 2);
        maycNfts.push({
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
        });
      }
    }
    const preCoinshares = await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address);

    await expect(contracts.bendStakeManager.unstakeBakc(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [constants.Zero.sub(unstakeAmount).sub(rewards), unstakeAmount.add(rewards), constants.Zero]
    );
    const sharesDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preCoinshares);
    expect(await contracts.bendCoinPool.convertToAssets(sharesDelta)).closeTo(bakcPoolRewards, 10);

    for (const id of unstakeBakcTokenId) {
      expect(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(pendingRewards);
    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(stakeAmount);
  });

  it("withdrawRefund: burn all stBAYC", async () => {
    let baycPooStakedAmount = constants.Zero;
    let baycPoolRewards = constants.Zero;
    let bakcPooStakedAmount = constants.Zero;
    let bakcPoolRewards = constants.Zero;
    for (const id of baycTokenIds) {
      baycPooStakedAmount = baycPooStakedAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
      baycPoolRewards = baycPoolRewards.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
      const pairStauts = await contracts.apeStaking.mainToBakc(1, id);
      if (pairStauts.isPaired) {
        bakcPooStakedAmount = bakcPooStakedAmount.add(
          (await contracts.apeStaking.nftPosition(3, pairStauts.tokenId)).stakedAmount
        );
        bakcPoolRewards = bakcPoolRewards.add(
          await contracts.apeStaking.pendingRewards(3, constants.AddressZero, pairStauts.tokenId)
        );
      }
    }
    expect(await contracts.bendStakeManager.refundOf(contracts.bayc.address))
      .eq(await contracts.bendStakeManager.refundOf(contracts.bakc.address))
      .eq(await contracts.bendStakeManager.totalRefund())
      .eq(0);
    const preBaycStakedAmount = await contracts.bendStakeManager.stakedApeCoin(1);
    const preBaycPendingRewards = await contracts.bendStakeManager.pendingRewards(1);

    const preBakcStakedAmount = await contracts.bendStakeManager.stakedApeCoin(3);
    const preBakcPendingRewards = await contracts.bendStakeManager.pendingRewards(3);

    await contracts.stBayc.connect(owner).burn(baycTokenIds);

    expect(
      (await contracts.bendStakeManager.refundOf(contracts.bayc.address)).add(
        await contracts.bendStakeManager.refundOf(contracts.bakc.address)
      )
    ).eq(await contracts.bendStakeManager.totalRefund());

    expect(await contracts.bendStakeManager.refundOf(contracts.bayc.address)).eq(
      baycPooStakedAmount.add(baycPoolRewards)
    );
    expect(await contracts.bendStakeManager.refundOf(contracts.bakc.address)).eq(
      bakcPooStakedAmount.add(bakcPoolRewards)
    );

    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(preBaycStakedAmount.sub(baycPooStakedAmount));
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(preBaycPendingRewards.sub(baycPoolRewards));

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(preBakcStakedAmount.sub(bakcPooStakedAmount));
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(preBakcPendingRewards.sub(bakcPoolRewards));

    const baycRewards = await contracts.baycStrategy.calculateNftRewards(baycPoolRewards);
    let preNftPool = await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bayc.address)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendStakeManager.address, contracts.nftVault.address, contracts.bendCoinPool.address],
      [
        constants.Zero,
        constants.Zero.sub(baycPooStakedAmount.add(baycPoolRewards)),
        baycPooStakedAmount.add(baycPoolRewards),
      ]
    );
    let nftPoolDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preNftPool);
    expect(await contracts.bendCoinPool.convertToAssets(nftPoolDelta)).closeTo(baycRewards, 10);

    const bakcRewards = await contracts.bakcStrategy.calculateNftRewards(bakcPoolRewards);
    preNftPool = await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bakc.address)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendStakeManager.address, contracts.nftVault.address, contracts.bendCoinPool.address],
      [
        constants.Zero,
        constants.Zero.sub(bakcPooStakedAmount.add(bakcPoolRewards)),
        bakcPooStakedAmount.add(bakcPoolRewards),
      ]
    );
    nftPoolDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address)).sub(preNftPool);
    expect(await contracts.bendCoinPool.convertToAssets(nftPoolDelta)).closeTo(bakcRewards, 10);
  });

  it("withdrawRefund: burn stBAYC with nonpaired bakc", async () => {
    let baycPooStakedAmount = constants.Zero;
    let baycPoolRewards = constants.Zero;
    let burnBaycTokenIds = [];
    for (const id of baycTokenIds) {
      const pairStauts = await contracts.apeStaking.mainToBakc(1, id);
      if (!pairStauts.isPaired) {
        burnBaycTokenIds.push(id);
        baycPooStakedAmount = baycPooStakedAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
        baycPoolRewards = baycPoolRewards.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
      }
    }
    expect(await contracts.bendStakeManager.refundOf(contracts.bayc.address))
      .eq(await contracts.bendStakeManager.totalRefund())
      .eq(0);

    const preBaycStakedAmount = await contracts.bendStakeManager.stakedApeCoin(1);
    const preBaycPendingRewards = await contracts.bendStakeManager.pendingRewards(1);

    const preBakcStakedAmount = await contracts.bendStakeManager.stakedApeCoin(3);
    const preBakcPendingRewards = await contracts.bendStakeManager.pendingRewards(3);

    await contracts.stBayc.connect(owner).burn(burnBaycTokenIds);

    expect(await contracts.bendStakeManager.refundOf(contracts.bayc.address)).eq(
      await contracts.bendStakeManager.totalRefund()
    );

    expect(await contracts.bendStakeManager.refundOf(contracts.bayc.address)).eq(
      baycPooStakedAmount.add(baycPoolRewards)
    );

    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(preBaycStakedAmount.sub(baycPooStakedAmount));
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(preBaycPendingRewards.sub(baycPoolRewards));

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(preBakcStakedAmount);
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(preBakcPendingRewards);

    const baycRewards = await contracts.baycStrategy.calculateNftRewards(baycPoolRewards);
    let preNftPool = await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bayc.address)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendStakeManager.address, contracts.nftVault.address, contracts.bendCoinPool.address],
      [
        constants.Zero,
        constants.Zero.sub(baycPooStakedAmount.add(baycPoolRewards)),
        baycPooStakedAmount.add(baycPoolRewards),
      ]
    );
    let nftPoolDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preNftPool);
    expect(await contracts.bendCoinPool.convertToAssets(nftPoolDelta)).closeTo(baycRewards, 10);
  });

  it("withdrawRefund: burn all stMAYC", async () => {
    let maycPooStakedAmount = constants.Zero;
    let maycPoolRewards = constants.Zero;
    let bakcPooStakedAmount = constants.Zero;
    let bakcPoolRewards = constants.Zero;
    for (const id of maycTokenIds) {
      maycPooStakedAmount = maycPooStakedAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
      maycPoolRewards = maycPoolRewards.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
      const pairStauts = await contracts.apeStaking.mainToBakc(2, id);
      if (pairStauts.isPaired) {
        bakcPooStakedAmount = bakcPooStakedAmount.add(
          (await contracts.apeStaking.nftPosition(3, pairStauts.tokenId)).stakedAmount
        );
        bakcPoolRewards = bakcPoolRewards.add(
          await contracts.apeStaking.pendingRewards(3, constants.AddressZero, pairStauts.tokenId)
        );
      }
    }
    expect(await contracts.bendStakeManager.refundOf(contracts.mayc.address))
      .eq(await contracts.bendStakeManager.refundOf(contracts.bakc.address))
      .eq(await contracts.bendStakeManager.totalRefund())
      .eq(0);
    const preMaycStakedAmount = await contracts.bendStakeManager.stakedApeCoin(2);
    const preMaycPendingRewards = await contracts.bendStakeManager.pendingRewards(2);

    const preBakcStakedAmount = await contracts.bendStakeManager.stakedApeCoin(3);
    const preBakcPendingRewards = await contracts.bendStakeManager.pendingRewards(3);

    await contracts.stMayc.connect(owner).burn(maycTokenIds);

    expect(
      (await contracts.bendStakeManager.refundOf(contracts.mayc.address)).add(
        await contracts.bendStakeManager.refundOf(contracts.bakc.address)
      )
    ).eq(await contracts.bendStakeManager.totalRefund());

    expect(await contracts.bendStakeManager.refundOf(contracts.mayc.address)).eq(
      maycPooStakedAmount.add(maycPoolRewards)
    );
    expect(await contracts.bendStakeManager.refundOf(contracts.bakc.address)).eq(
      bakcPooStakedAmount.add(bakcPoolRewards)
    );

    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(preMaycStakedAmount.sub(maycPooStakedAmount));
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(preMaycPendingRewards.sub(maycPoolRewards));

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(preBakcStakedAmount.sub(bakcPooStakedAmount));
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(preBakcPendingRewards.sub(bakcPoolRewards));

    const maycRewards = await contracts.maycStrategy.calculateNftRewards(maycPoolRewards);
    let preNftPool = await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.mayc.address)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendStakeManager.address, contracts.nftVault.address, contracts.bendCoinPool.address],
      [
        constants.Zero,
        constants.Zero.sub(maycPooStakedAmount.add(maycPoolRewards)),
        maycPooStakedAmount.add(maycPoolRewards),
      ]
    );
    let nftPoolDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preNftPool);

    expect(await contracts.bendCoinPool.convertToAssets(nftPoolDelta)).closeTo(maycRewards, 10);

    const bakcRewards = await contracts.bakcStrategy.calculateNftRewards(bakcPoolRewards);
    preNftPool = await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bakc.address)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendStakeManager.address, contracts.nftVault.address, contracts.bendCoinPool.address],
      [
        constants.Zero,
        constants.Zero.sub(bakcPooStakedAmount.add(bakcPoolRewards)),
        bakcPooStakedAmount.add(bakcPoolRewards),
      ]
    );
    nftPoolDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address)).sub(preNftPool);
    expect(await contracts.bendCoinPool.convertToAssets(nftPoolDelta)).closeTo(bakcRewards, 10);
  });

  it("withdrawRefund: burn stMAYC with nonpaired bakc", async () => {
    let maycPooStakedAmount = constants.Zero;
    let maycPoolRewards = constants.Zero;
    let burnMaycTokenIds = [];
    for (const id of maycTokenIds) {
      const pairStauts = await contracts.apeStaking.mainToBakc(2, id);
      if (!pairStauts.isPaired) {
        burnMaycTokenIds.push(id);
        maycPooStakedAmount = maycPooStakedAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
        maycPoolRewards = maycPoolRewards.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
      }
    }
    expect(await contracts.bendStakeManager.refundOf(contracts.mayc.address))
      .eq(await contracts.bendStakeManager.totalRefund())
      .eq(0);

    const preMaycStakedAmount = await contracts.bendStakeManager.stakedApeCoin(2);
    const preMaycPendingRewards = await contracts.bendStakeManager.pendingRewards(2);

    const preBakcStakedAmount = await contracts.bendStakeManager.stakedApeCoin(3);
    const preBakcPendingRewards = await contracts.bendStakeManager.pendingRewards(3);

    await contracts.stMayc.connect(owner).burn(burnMaycTokenIds);

    expect(await contracts.bendStakeManager.refundOf(contracts.mayc.address)).eq(
      await contracts.bendStakeManager.totalRefund()
    );

    expect(await contracts.bendStakeManager.refundOf(contracts.mayc.address)).eq(
      maycPooStakedAmount.add(maycPoolRewards)
    );

    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(preMaycStakedAmount.sub(maycPooStakedAmount));
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(preMaycPendingRewards.sub(maycPoolRewards));

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(preBakcStakedAmount);
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(preBakcPendingRewards);

    const maycRewards = await contracts.maycStrategy.calculateNftRewards(maycPoolRewards);
    let preNftPool = await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.mayc.address)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendStakeManager.address, contracts.nftVault.address, contracts.bendCoinPool.address],
      [
        constants.Zero,
        constants.Zero.sub(maycPooStakedAmount.add(maycPoolRewards)),
        maycPooStakedAmount.add(maycPoolRewards),
      ]
    );
    let nftPoolDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preNftPool);

    expect(await contracts.bendCoinPool.convertToAssets(nftPoolDelta)).closeTo(maycRewards, 10);
  });

  it("withdrawRefund: burn part of stBAKC", async () => {
    let pooStakedAmount = constants.Zero;
    let poolRewards = constants.Zero;
    let tokenIds = shuffledSubarray(bakcTokenIds);
    for (const id of tokenIds) {
      pooStakedAmount = pooStakedAmount.add((await contracts.apeStaking.nftPosition(3, id)).stakedAmount);
      poolRewards = poolRewards.add(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id));
    }
    expect(await contracts.bendStakeManager.refundOf(contracts.bakc.address))
      .eq(await contracts.bendStakeManager.totalRefund())
      .eq(0);

    const preStakedAmount = await contracts.bendStakeManager.stakedApeCoin(3);
    const prePendingRewards = await contracts.bendStakeManager.pendingRewards(3);

    await contracts.stBakc.connect(owner).burn(tokenIds);

    expect(await contracts.bendStakeManager.refundOf(contracts.bakc.address)).eq(
      await contracts.bendStakeManager.totalRefund()
    );

    expect(await contracts.bendStakeManager.refundOf(contracts.bakc.address)).eq(pooStakedAmount.add(poolRewards));

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(preStakedAmount.sub(pooStakedAmount));
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(prePendingRewards.sub(poolRewards));

    const bakcRewards = await contracts.bakcStrategy.calculateNftRewards(poolRewards);
    let preNftPool = await contracts.bendCoinPool.balanceOf(contracts.bendCoinPool.address);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bakc.address)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendStakeManager.address, contracts.nftVault.address, contracts.bendCoinPool.address],
      [constants.Zero, constants.Zero.sub(pooStakedAmount.add(poolRewards)), pooStakedAmount.add(poolRewards)]
    );
    let nftPoolDelta = (await contracts.bendCoinPool.balanceOf(contracts.bendNftPool.address)).sub(preNftPool);

    expect(await contracts.bendCoinPool.convertToAssets(nftPoolDelta)).closeTo(bakcRewards, 10);
  });
});
