import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { advanceHours, makeBN18, mintNft, randomUint, shuffledSubarray } from "./utils";
import { BigNumber, constants, Contract, ContractTransaction } from "ethers";
import { IApeCoinStaking, IRewardsStrategy, IStakeManager } from "../../typechain-types";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";

makeSuite("BendStakeManager", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let bot: SignerWithAddress;
  let feeRecipient: SignerWithAddress;
  let fee: number;
  let lastRevert: string;
  let baycTokenIds: number[];
  let maycTokenIds: number[];
  let bakcTokenIds: number[];
  const APE_COIN_AMOUNT = 70000;

  before(async () => {
    owner = env.accounts[1];
    feeRecipient = env.accounts[2];
    bot = env.accounts[3];
    fee = 500;
    baycTokenIds = [0, 1, 2, 3, 4, 5];
    await mintNft(owner, contracts.bayc, baycTokenIds);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    maycTokenIds = [6, 7, 8, 9, 10];
    await mintNft(owner, contracts.mayc, maycTokenIds);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    bakcTokenIds = [10, 11, 12, 13, 14];
    await mintNft(owner, contracts.bakc, bakcTokenIds);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    await contracts.bendNftPool
      .connect(owner)
      .deposit(
        [contracts.bayc.address, contracts.mayc.address, contracts.bakc.address],
        [baycTokenIds, maycTokenIds, bakcTokenIds]
      );

    await contracts.apeCoin.connect(owner).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.bendCoinPool.connect(owner).deposit(makeBN18(APE_COIN_AMOUNT), owner.address);

    await impersonateAccount(contracts.bendCoinPool.address);
    await setBalance(contracts.bendCoinPool.address, makeBN18(1));

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("onlyApe: reverts", async () => {
    await expect(
      contracts.bendStakeManager.updateRewardsStrategy(constants.AddressZero, constants.AddressZero)
    ).revertedWith("BendStakeManager: nft must be ape");
    await expect(contracts.bendStakeManager.refundOf(constants.AddressZero)).revertedWith(
      "BendStakeManager: nft must be ape"
    );
  });

  it("onlyBot: reverts", async () => {
    const args: IStakeManager.CompoundArgsStruct = {
      claimCoinPool: true,
      claim: {
        bayc: [],
        mayc: [],
        baycPairs: [],
        maycPairs: [],
      },
      unstake: {
        bayc: [],
        mayc: [],
        baycPairs: [],
        maycPairs: [],
      },
      stake: {
        bayc: [],
        mayc: [],
        baycPairs: [],
        maycPairs: [],
      },
      coinStakeThreshold: 0,
    };
    await expect(contracts.bendStakeManager.compound(args)).revertedWith("BendStakeManager: caller is not bot admin");
  });

  it("onlyCoinPool: reverts", async () => {
    await expect(contracts.bendStakeManager.withdrawApeCoin(constants.Zero)).revertedWith(
      "BendStakeManager: caller is not coin pool"
    );
  });

  it("onlyOwner: reverts", async () => {
    await expect(contracts.bendStakeManager.connect(owner).updateBotAdmin(constants.AddressZero)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(contracts.bendStakeManager.connect(owner).updateFee(constants.Zero)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(contracts.bendStakeManager.connect(owner).updateFeeRecipient(constants.AddressZero)).revertedWith(
      "Ownable: caller is not the owner"
    );
    await expect(
      contracts.bendStakeManager.connect(owner).updateRewardsStrategy(constants.AddressZero, constants.AddressZero)
    ).revertedWith("Ownable: caller is not the owner");
  });

  const excludeFee = (amount: BigNumber) => {
    return amount.sub(amount.mul(fee).div(10000));
  };

  it("updateFee", async () => {
    expect(await contracts.bendStakeManager.fee()).eq(0);
    await expect(contracts.bendStakeManager.updateFee(1001)).revertedWith("BendStakeManager: invalid fee");
    await contracts.bendStakeManager.updateFee(fee);
    expect(await contracts.bendStakeManager.fee()).eq(fee);
    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("updateFeeRecipient", async () => {
    expect(await contracts.bendStakeManager.feeRecipient()).eq(constants.AddressZero);
    await expect(contracts.bendStakeManager.updateFeeRecipient(constants.AddressZero)).revertedWith(
      "BendStakeManager: invalid fee recipient"
    );
    await contracts.bendStakeManager.updateFeeRecipient(feeRecipient.address);
    expect(await contracts.bendStakeManager.feeRecipient()).eq(feeRecipient.address);
    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("updateBotAdmin", async () => {
    // expect(await (contracts.bendStakeManager as Contract).botAdmin()).eq(constants.AddressZero);
    await contracts.bendStakeManager.updateBotAdmin(bot.address);
    expect(await (contracts.bendStakeManager as Contract).botAdmin()).eq(bot.address);
    // revert bot admin to default account to simple follow tests
    await contracts.bendStakeManager.updateBotAdmin(env.admin.address);
    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("updateRewardsStrategy", async () => {
    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.bayc.address)).eq(
      contracts.baycStrategy.address
    );

    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.mayc.address)).eq(
      contracts.maycStrategy.address
    );
    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.bakc.address)).eq(
      contracts.bakcStrategy.address
    );

    contracts.bendStakeManager.updateRewardsStrategy(contracts.bayc.address, contracts.bayc.address);
    contracts.bendStakeManager.updateRewardsStrategy(contracts.mayc.address, contracts.mayc.address);
    contracts.bendStakeManager.updateRewardsStrategy(contracts.bakc.address, contracts.bakc.address);

    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.bayc.address)).eq(
      contracts.bayc.address
    );

    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.mayc.address)).eq(
      contracts.mayc.address
    );
    expect(await (contracts.bendStakeManager as Contract).rewardsStrategies(contracts.bakc.address)).eq(
      contracts.bakc.address
    );
  });

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
    const realRewards = await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0);

    expect(excludeFee(realRewards)).eq(rewards);

    await expect(contracts.bendStakeManager.claimApeCoin()).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(realRewards), rewards]
    );

    expect(await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0))
      .eq(await contracts.bendStakeManager.pendingRewards(0))
      .eq(0);
  });

  it("unstakeApeCoin: unstake partially", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    let realRewards = await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0);
    const unstakeAmount = (await contracts.bendStakeManager.stakedApeCoin(0)).div(2);

    expect(excludeFee(realRewards)).eq(rewards);

    await expect(contracts.bendStakeManager.unstakeApeCoin(unstakeAmount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(unstakeAmount), unstakeAmount]
    );

    // no rewards claimed
    realRewards = await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0);
    expect(excludeFee(realRewards))
      .eq(await contracts.bendStakeManager.pendingRewards(0))
      .eq(rewards);
  });

  it("unstakeApeCoin: unstake fully", async () => {
    await advanceHours(10);
    let realRewards = await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0);
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(0);

    expect(excludeFee(realRewards)).eq(rewards);

    await expect(contracts.bendStakeManager.unstakeApeCoin(unstakeAmount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(unstakeAmount).sub(realRewards), unstakeAmount.add(rewards)]
    );
    realRewards = await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0);
    expect(excludeFee(realRewards))
      .eq(await contracts.bendStakeManager.pendingRewards(0))
      .eq(constants.Zero);
  });

  it("prepareApeCoin: from pending ape coin & rewards", async () => {
    await advanceHours(10);
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    const realRewards = await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0);
    const fee = realRewards.sub(rewards);
    const requiredAmount = pendingApeCoin.add(makeBN18(1));

    await expect(contracts.bendStakeManager.prepareApeCoin(requiredAmount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [rewards.sub(requiredAmount), constants.Zero.sub(realRewards), requiredAmount.add(fee)]
    );
    expect(await contracts.bendCoinPool.pendingApeCoin()).eq(pendingApeCoin.add(rewards).sub(requiredAmount));
  });

  it("prepareApeCoin: from pending ape coin & rewards & staked", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(0);
    const realRewards = await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0);
    const fee = realRewards.sub(rewards);
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();

    const requiredAmount = pendingApeCoin.add(rewards).add(makeBN18(1));

    await expect(contracts.bendStakeManager.prepareApeCoin(requiredAmount)).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      [constants.Zero.sub(pendingApeCoin), constants.Zero.sub(realRewards).sub(makeBN18(1)), requiredAmount.add(fee)]
    );
    expect(await contracts.bendCoinPool.pendingApeCoin()).eq(constants.Zero);
  });

  const expectStake = async (stakeAction: () => Promise<ContractTransaction>, requiredAmount: BigNumber) => {
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    const pendingRewards = await contracts.bendStakeManager.pendingRewards(0);
    const fee = (await contracts.apeStaking.pendingRewards(0, contracts.bendStakeManager.address, 0)).sub(
      pendingRewards
    );
    let changes = [];
    if (requiredAmount.lte(pendingApeCoin)) {
      // pending ape coin only
      changes = [constants.Zero.sub(requiredAmount), requiredAmount, constants.Zero];
    } else if (requiredAmount.gt(pendingApeCoin) && pendingRewards.gte(requiredAmount.sub(pendingApeCoin))) {
      // pending ape coin & rewards
      changes = [pendingRewards.sub(requiredAmount), requiredAmount.sub(pendingRewards).sub(fee), fee];
    } else {
      // pending ape coin & rewards & staked
      changes = [constants.Zero.sub(pendingApeCoin), pendingApeCoin.sub(fee), fee];
    }
    return await expect(stakeAction()).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.apeStaking.address, contracts.bendStakeManager.address],
      changes
    );
  };

  it("stakeBayc", async () => {
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(1);
    const requiredAmount = makeBN18(10094 * baycTokenIds.length);
    await expectStake(() => {
      return contracts.bendStakeManager.stakeBayc(baycTokenIds);
    }, requiredAmount);

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
    let realRewards = constants.Zero;

    for (const id of baycTokenIds) {
      realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
    }
    const fee = realRewards.sub(rewards);
    expect(rewards).eq(excludeFee(realRewards));

    const nftRewards = await calculateNftRewards(rewards, contracts.baycStrategy);

    await expect(contracts.bendStakeManager.claimBayc(baycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [constants.Zero.sub(realRewards), rewards.sub(nftRewards), nftRewards, fee]
    );

    for (const id of baycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(0);
  });

  const calculateNftRewards = async (rewards: BigNumber, strategy: IRewardsStrategy) => {
    return rewards.mul(await strategy.getNftRewardsShare()).div(10000);
  };

  it("unstakeBayc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(1);
    const realRewards = await contracts.bendStakeManager.pendingRewardsIncludeFee(1);
    const fee = realRewards.sub(rewards);

    const baycPoolRewards = await calculateNftRewards(rewards, contracts.baycStrategy);

    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(1);

    await expect(contracts.bendStakeManager.unstakeBayc(baycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(unstakeAmount).sub(realRewards),
        unstakeAmount.add(rewards.sub(baycPoolRewards)),
        baycPoolRewards,
        fee,
      ]
    );

    for (const id of baycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(0);
  });

  it("unstakeBayc: unstake partially", async () => {
    await advanceHours(10);
    let realRewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let pendingRewards = constants.Zero;
    const unstakeBaycTokenId = [];
    for (const [i, id] of baycTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeBaycTokenId.push(id);
        realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
      } else {
        pendingRewards = pendingRewards.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
      }
    }
    const rewards = excludeFee(realRewards);
    const fee = realRewards.sub(rewards);

    const baycPoolRewards = await calculateNftRewards(rewards, contracts.baycStrategy);
    await expect(contracts.bendStakeManager.unstakeBayc(unstakeBaycTokenId)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(unstakeAmount).sub(realRewards),
        unstakeAmount.add(rewards.sub(baycPoolRewards)),
        baycPoolRewards,
        fee,
      ]
    );

    for (const id of unstakeBaycTokenId) {
      expect(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(1)).eq(excludeFee(pendingRewards));
    expect(await contracts.bendStakeManager.stakedApeCoin(1)).eq(stakeAmount);
  });

  it("stakeMayc", async () => {
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(2);
    const requiredAmount = makeBN18(2042 * maycTokenIds.length);
    const preStakedTotal = await contracts.apeStaking.stakedTotal(contracts.nftVault.address);
    await expectStake(() => {
      return contracts.bendStakeManager.stakeMayc(maycTokenIds);
    }, requiredAmount);

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
    let realRewards = constants.Zero;

    for (const id of maycTokenIds) {
      realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
    }
    const fee = realRewards.sub(rewards);

    expect(rewards).eq(excludeFee(realRewards));

    const nftRewards = await calculateNftRewards(rewards, contracts.maycStrategy);

    await expect(contracts.bendStakeManager.claimMayc(maycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [constants.Zero.sub(realRewards), rewards.sub(nftRewards), nftRewards, fee]
    );

    for (const id of maycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(0);
  });

  it("unstakeMayc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(2);
    const realRewards = await contracts.bendStakeManager.pendingRewardsIncludeFee(2);
    const fee = realRewards.sub(rewards);
    const maycPoolRewards = await calculateNftRewards(rewards, contracts.maycStrategy);
    const unstakeAmount = await contracts.bendStakeManager.stakedApeCoin(2);

    await expect(contracts.bendStakeManager.unstakeMayc(maycTokenIds)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(unstakeAmount).sub(realRewards),
        unstakeAmount.add(rewards.sub(maycPoolRewards)),
        maycPoolRewards,
        fee,
      ]
    );

    for (const id of maycTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(0);
  });

  it("unstakeMayc: unstake partially", async () => {
    await advanceHours(10);
    let realRewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let pendingRewards = constants.Zero;
    const unstakeMaycTokenId = [];
    for (const [i, id] of maycTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeMaycTokenId.push(id);
        realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
      } else {
        pendingRewards = pendingRewards.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
      }
    }
    const rewards = excludeFee(realRewards);
    const fee = realRewards.sub(rewards);

    const maycPoolRewards = await calculateNftRewards(rewards, contracts.maycStrategy);
    await expect(contracts.bendStakeManager.unstakeMayc(unstakeMaycTokenId)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(unstakeAmount).sub(realRewards),
        unstakeAmount.add(rewards.sub(maycPoolRewards)),
        maycPoolRewards,
        fee,
      ]
    );

    for (const id of unstakeMaycTokenId) {
      expect(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(2)).eq(excludeFee(pendingRewards));
    expect(await contracts.bendStakeManager.stakedApeCoin(2)).eq(stakeAmount);
  });

  it("stakeBakc", async () => {
    await advanceHours(10);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(3);
    const requiredAmount = makeBN18(856 * maycTokenIds.length);
    const preStakedTotal = await contracts.apeStaking.stakedTotal(contracts.nftVault.address);

    const baycNfts: IApeCoinStaking.PairNftStruct[] = [];
    const maycNfts: IApeCoinStaking.PairNftStruct[] = [];
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

    await expectStake(() => {
      return contracts.bendStakeManager.stakeBakc(baycNfts, maycNfts);
    }, requiredAmount);

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
    let realRewards = constants.Zero;

    for (const id of bakcTokenIds) {
      realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id));
    }
    expect(rewards).eq(excludeFee(realRewards));
    const fee = realRewards.sub(rewards);

    const bakcPoolRewards = await calculateNftRewards(rewards, contracts.bakcStrategy);

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

    await expect(contracts.bendStakeManager.claimBakc(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [constants.Zero.sub(realRewards), rewards.sub(bakcPoolRewards), bakcPoolRewards, fee]
    );

    for (const id of bakcTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(0);
  });

  it("unstakeBakc: unstake fully", async () => {
    await advanceHours(10);
    const rewards = await contracts.bendStakeManager.pendingRewards(3);
    const realRewards = await contracts.bendStakeManager.pendingRewardsIncludeFee(3);
    const fee = realRewards.sub(rewards);
    const bakcPoolRewards = await calculateNftRewards(rewards, contracts.bakcStrategy);
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

    await expect(contracts.bendStakeManager.unstakeBakc(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(unstakeAmount).sub(realRewards),
        unstakeAmount.add(rewards.sub(bakcPoolRewards)),
        bakcPoolRewards,
        fee,
      ]
    );

    for (const id of bakcTokenIds) {
      expect(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(0);
  });

  it("unstakBakc: unstake partially", async () => {
    await advanceHours(10);
    let realRewards = constants.Zero;
    let unstakeAmount = constants.Zero;
    let stakeAmount = constants.Zero;
    let realPendingRewards = constants.Zero;
    const unstakeBakcTokenId = [];

    for (const [i, id] of bakcTokenIds.entries()) {
      if (i % 2 === 1) {
        unstakeBakcTokenId.push(id);
        realRewards = realRewards.add(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id));
        unstakeAmount = unstakeAmount.add((await contracts.apeStaking.nftPosition(3, id)).stakedAmount);
      } else {
        realPendingRewards = realPendingRewards.add(
          await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id)
        );
        stakeAmount = stakeAmount.add((await contracts.apeStaking.nftPosition(3, id)).stakedAmount);
      }
    }
    const rewards = excludeFee(realRewards);
    const fee = realRewards.sub(rewards);
    const bakcPoolRewards = await calculateNftRewards(rewards, contracts.bakcStrategy);

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

    await expect(contracts.bendStakeManager.unstakeBakc(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.apeStaking.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(unstakeAmount).sub(realRewards),
        unstakeAmount.add(rewards.sub(bakcPoolRewards)),
        bakcPoolRewards,
        fee,
      ]
    );

    for (const id of unstakeBakcTokenId) {
      expect(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id)).eq(0);
    }
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(excludeFee(realPendingRewards));
    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(stakeAmount);
  });

  it("withdrawRefund: burn all stBAYC", async () => {
    let baycPooStakedAmount = constants.Zero;
    let realBaycPoolRewards = constants.Zero;
    let bakcPooStakedAmount = constants.Zero;
    let realBakcPoolRewards = constants.Zero;
    for (const id of baycTokenIds) {
      baycPooStakedAmount = baycPooStakedAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
      realBaycPoolRewards = realBaycPoolRewards.add(
        await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id)
      );
      const pairStauts = await contracts.apeStaking.mainToBakc(1, id);
      if (pairStauts.isPaired) {
        bakcPooStakedAmount = bakcPooStakedAmount.add(
          (await contracts.apeStaking.nftPosition(3, pairStauts.tokenId)).stakedAmount
        );
        realBakcPoolRewards = realBakcPoolRewards.add(
          await contracts.apeStaking.pendingRewards(3, constants.AddressZero, pairStauts.tokenId)
        );
      }
    }
    const baycPoolRewards = excludeFee(realBaycPoolRewards);
    const bakcPoolRewards = excludeFee(realBakcPoolRewards);
    const baycFee = realBaycPoolRewards.sub(baycPoolRewards);
    const bakcFee = realBakcPoolRewards.sub(bakcPoolRewards);

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

    const baycRewards = await calculateNftRewards(baycPoolRewards, contracts.baycStrategy);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bayc.address)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.nftVault.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(baycPooStakedAmount.add(realBaycPoolRewards)),
        baycPooStakedAmount.add(baycPoolRewards.sub(baycRewards)),
        baycRewards,
        baycFee,
      ]
    );

    const bakcRewards = await calculateNftRewards(bakcPoolRewards, contracts.bakcStrategy);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bakc.address)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.nftVault.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(bakcPooStakedAmount.add(bakcPoolRewards)),
        bakcPooStakedAmount.add(bakcPoolRewards.sub(bakcRewards)),
        bakcRewards,
        bakcFee,
      ]
    );
  });

  it("withdrawRefund: burn stBAYC with nonpaired bakc", async () => {
    let baycPooStakedAmount = constants.Zero;
    let realBaycPoolRewards = constants.Zero;
    let burnBaycTokenIds = [];
    for (const id of baycTokenIds) {
      const pairStauts = await contracts.apeStaking.mainToBakc(1, id);
      if (!pairStauts.isPaired) {
        burnBaycTokenIds.push(id);
        baycPooStakedAmount = baycPooStakedAmount.add((await contracts.apeStaking.nftPosition(1, id)).stakedAmount);
        realBaycPoolRewards = realBaycPoolRewards.add(
          await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id)
        );
      }
    }
    expect(await contracts.bendStakeManager.refundOf(contracts.bayc.address))
      .eq(await contracts.bendStakeManager.totalRefund())
      .eq(0);
    const baycPoolRewards = excludeFee(realBaycPoolRewards);
    const fee = realBaycPoolRewards.sub(baycPoolRewards);

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
    expect(await contracts.bendStakeManager.pendingRewards(1)).closeTo(preBaycPendingRewards.sub(baycPoolRewards), 5);

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(preBakcStakedAmount);
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(preBakcPendingRewards);

    const baycRewards = await calculateNftRewards(baycPoolRewards, contracts.baycStrategy);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bayc.address)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.nftVault.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(baycPooStakedAmount.add(realBaycPoolRewards)),
        baycPooStakedAmount.add(baycPoolRewards.sub(baycRewards)),
        baycRewards,
        fee,
      ]
    );
  });

  it("withdrawRefund: burn all stMAYC", async () => {
    let maycPooStakedAmount = constants.Zero;
    let realMaycPoolRewards = constants.Zero;
    let bakcPooStakedAmount = constants.Zero;
    let realBakcPoolRewards = constants.Zero;
    for (const id of maycTokenIds) {
      maycPooStakedAmount = maycPooStakedAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
      realMaycPoolRewards = realMaycPoolRewards.add(
        await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id)
      );
      const pairStauts = await contracts.apeStaking.mainToBakc(2, id);
      if (pairStauts.isPaired) {
        bakcPooStakedAmount = bakcPooStakedAmount.add(
          (await contracts.apeStaking.nftPosition(3, pairStauts.tokenId)).stakedAmount
        );
        realBakcPoolRewards = realBakcPoolRewards.add(
          await contracts.apeStaking.pendingRewards(3, constants.AddressZero, pairStauts.tokenId)
        );
      }
    }
    const maycPoolRewards = excludeFee(realMaycPoolRewards);
    const maycFee = realMaycPoolRewards.sub(maycPoolRewards);
    const bakcPoolRewards = excludeFee(realBakcPoolRewards);
    const bakcFee = realBakcPoolRewards.sub(bakcPoolRewards);

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

    const maycRewards = await calculateNftRewards(maycPoolRewards, contracts.maycStrategy);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.mayc.address)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.nftVault.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(maycPooStakedAmount.add(realMaycPoolRewards)),
        maycPooStakedAmount.add(maycPoolRewards.sub(maycRewards)),
        maycRewards,
        maycFee,
      ]
    );

    const bakcRewards = await calculateNftRewards(bakcPoolRewards, contracts.bakcStrategy);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bakc.address)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.nftVault.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(bakcPooStakedAmount.add(bakcPoolRewards)),
        bakcPooStakedAmount.add(bakcPoolRewards.sub(bakcRewards)),
        bakcRewards,
        bakcFee,
      ]
    );
  });

  it("withdrawRefund: burn stMAYC with nonpaired bakc", async () => {
    let maycPooStakedAmount = constants.Zero;
    let realMaycPoolRewards = constants.Zero;
    let burnMaycTokenIds = [];
    for (const id of maycTokenIds) {
      const pairStauts = await contracts.apeStaking.mainToBakc(2, id);
      if (!pairStauts.isPaired) {
        burnMaycTokenIds.push(id);
        maycPooStakedAmount = maycPooStakedAmount.add((await contracts.apeStaking.nftPosition(2, id)).stakedAmount);
        realMaycPoolRewards = realMaycPoolRewards.add(
          await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id)
        );
      }
    }
    const maycPoolRewards = excludeFee(realMaycPoolRewards);
    const fee = realMaycPoolRewards.sub(maycPoolRewards);

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
    expect(await contracts.bendStakeManager.pendingRewards(2)).closeTo(preMaycPendingRewards.sub(maycPoolRewards), 5);

    expect(await contracts.bendStakeManager.stakedApeCoin(3)).eq(preBakcStakedAmount);
    expect(await contracts.bendStakeManager.pendingRewards(3)).eq(preBakcPendingRewards);

    const maycRewards = await calculateNftRewards(maycPoolRewards, contracts.maycStrategy);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.mayc.address)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.nftVault.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(maycPooStakedAmount.add(realMaycPoolRewards)),
        maycPooStakedAmount.add(maycPoolRewards.sub(maycRewards)),
        maycRewards,
        fee,
      ]
    );
  });

  it("withdrawRefund: burn part of stBAKC", async () => {
    let pooStakedAmount = constants.Zero;
    let realPoolRewards = constants.Zero;
    let tokenIds = shuffledSubarray(bakcTokenIds);
    for (const id of tokenIds) {
      pooStakedAmount = pooStakedAmount.add((await contracts.apeStaking.nftPosition(3, id)).stakedAmount);
      realPoolRewards = realPoolRewards.add(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id));
    }
    const poolRewards = excludeFee(realPoolRewards);
    const fee = realPoolRewards.sub(poolRewards);

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

    const bakcRewards = await calculateNftRewards(poolRewards, contracts.bakcStrategy);

    await expect(contracts.bendStakeManager.withdrawRefund(contracts.bakc.address)).changeTokenBalances(
      contracts.apeCoin,
      [
        contracts.nftVault.address,
        contracts.bendCoinPool.address,
        contracts.bendNftPool.address,
        contracts.bendStakeManager.address,
      ],
      [
        constants.Zero.sub(pooStakedAmount.add(realPoolRewards)),
        pooStakedAmount.add(poolRewards.sub(bakcRewards)),
        bakcRewards,
        fee,
      ]
    );
  });

  it("withdrawTotalRefund", async () => {
    await contracts.stBayc.connect(owner).burn(shuffledSubarray(baycTokenIds));
    await contracts.stMayc.connect(owner).burn(shuffledSubarray(maycTokenIds));
    await contracts.stBakc.connect(owner).burn(shuffledSubarray(bakcTokenIds));
    const totalRefund = await contracts.bendStakeManager.totalRefund();
    expect(totalRefund).closeTo(
      (await contracts.bendStakeManager.refundOf(contracts.bayc.address))
        .add(await contracts.bendStakeManager.refundOf(contracts.mayc.address))
        .add(await contracts.bendStakeManager.refundOf(contracts.bakc.address)),
      5
    );
    const preNftPoolBalance = await contracts.apeCoin.balanceOf(contracts.bendNftPool.address);
    const preCoinPoolBalance = await contracts.apeCoin.balanceOf(contracts.bendCoinPool.address);
    const preStakeManagerBalance = await contracts.apeCoin.balanceOf(contracts.bendStakeManager.address);
    const preNftVaultBalance = await contracts.apeCoin.balanceOf(contracts.nftVault.address);
    await snapshots.capture("withdrawTotalRefund");

    await contracts.bendStakeManager.withdrawRefund(contracts.bayc.address);
    await contracts.bendStakeManager.withdrawRefund(contracts.mayc.address);
    await contracts.bendStakeManager.withdrawRefund(contracts.bakc.address);

    let nftPoolBalance = await contracts.apeCoin.balanceOf(contracts.bendNftPool.address);
    let coinPoolBalance = await contracts.apeCoin.balanceOf(contracts.bendCoinPool.address);
    let stakeManagerBalance = await contracts.apeCoin.balanceOf(contracts.bendStakeManager.address);
    let nftVaultBalance = await contracts.apeCoin.balanceOf(contracts.nftVault.address);
    let fee = stakeManagerBalance.sub(preStakeManagerBalance);

    expect(preNftVaultBalance.sub(nftVaultBalance).sub(fee)).closeTo(totalRefund, 5);

    expect(preNftVaultBalance.sub(nftVaultBalance)).closeTo(
      coinPoolBalance.sub(preCoinPoolBalance).add(nftPoolBalance.sub(preNftPoolBalance)).add(fee),
      5
    );
    await snapshots.revert("withdrawTotalRefund");

    await contracts.bendStakeManager.withdrawTotalRefund();
    nftPoolBalance = await contracts.apeCoin.balanceOf(contracts.bendNftPool.address);
    coinPoolBalance = await contracts.apeCoin.balanceOf(contracts.bendCoinPool.address);
    stakeManagerBalance = await contracts.apeCoin.balanceOf(contracts.bendStakeManager.address);
    nftVaultBalance = await contracts.apeCoin.balanceOf(contracts.nftVault.address);
    fee = stakeManagerBalance.sub(preStakeManagerBalance);

    expect(preNftVaultBalance.sub(nftVaultBalance).sub(fee)).closeTo(totalRefund, 5);

    expect(preNftVaultBalance.sub(nftVaultBalance)).closeTo(
      coinPoolBalance.sub(preCoinPoolBalance).add(nftPoolBalance.sub(preNftPoolBalance)).add(fee),
      5
    );
  });

  it("totalStakedApeCoin", async () => {
    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(
      (await contracts.bendStakeManager.stakedApeCoin(0))
        .add(await contracts.bendStakeManager.stakedApeCoin(1))
        .add(await contracts.bendStakeManager.stakedApeCoin(2))
        .add(await contracts.bendStakeManager.stakedApeCoin(3))
    );
    await contracts.bendStakeManager.unstakeBayc(baycTokenIds);

    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(
      (await contracts.bendStakeManager.stakedApeCoin(0))
        .add(await contracts.bendStakeManager.stakedApeCoin(2))
        .add(await contracts.bendStakeManager.stakedApeCoin(3))
    );
    await contracts.bendStakeManager.unstakeMayc(maycTokenIds);
    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(
      (await contracts.bendStakeManager.stakedApeCoin(0)).add(await contracts.bendStakeManager.stakedApeCoin(3))
    );
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
    await contracts.bendStakeManager.unstakeBakc(baycNfts, maycNfts);
    const stakedAmount = await contracts.bendStakeManager.stakedApeCoin(0);
    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(stakedAmount);
    await contracts.bendStakeManager.unstakeApeCoin(stakedAmount);
    expect(await contracts.bendStakeManager.totalStakedApeCoin()).eq(0);
    expect(await contracts.bendStakeManager.stakedApeCoin(0)).eq(0);
    expect((await contracts.apeStaking.addressPosition(contracts.bendStakeManager.address)).stakedAmount).eq(0);
  });

  it("withdrawApeCoin: someone burn stNft and withdraw all of ape coin", async () => {
    await advanceHours(10);
    await contracts.stBakc.connect(owner).burn([10]);
    lastRevert = "withdrawApeCoin";
    await snapshots.capture(lastRevert);
    const withdrawAmount = (await contracts.bendStakeManager.totalStakedApeCoin())
      .add(await contracts.bendStakeManager.totalPendingRewards())
      .add(await contracts.bendStakeManager.totalRefund());

    const coinPoolSigner = await ethers.getSigner(contracts.bendCoinPool.address);
    const preBalance = await contracts.apeCoin.balanceOf(contracts.bendCoinPool.address);
    const preNftPoolBalance = await contracts.apeCoin.balanceOf(contracts.bendNftPool.address);
    await contracts.bendStakeManager.connect(coinPoolSigner).withdrawApeCoin(withdrawAmount);

    const coinPoolReceived = (await contracts.apeCoin.balanceOf(contracts.bendCoinPool.address)).sub(preBalance);
    const nftPoolReceived = (await contracts.apeCoin.balanceOf(contracts.bendNftPool.address)).sub(preNftPoolBalance);
    expect(coinPoolReceived.add(nftPoolReceived)).closeTo(withdrawAmount, 5);
  });

  it("withdrawApeCoin: refund only", async () => {
    const refundDetails = await contracts.bendStakeManager.refundOfDetails(contracts.bakc.address);
    const nftRewards = await calculateNftRewards(refundDetails.reward, contracts.bakcStrategy);
    const coinPoolSigner = await ethers.getSigner(contracts.bendCoinPool.address);
    await expect(
      contracts.bendStakeManager.connect(coinPoolSigner).withdrawApeCoin(refundDetails.principal)
    ).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [refundDetails.principal.add(refundDetails.reward.sub(nftRewards)), nftRewards]
    );
  });

  it("withdrawApeCoin: refund & coin pool rewards", async () => {
    const refundDetails = await contracts.bendStakeManager.refundOfDetails(contracts.bakc.address);
    const nftRewards = await calculateNftRewards(refundDetails.reward, contracts.bakcStrategy);
    const coinPoolRewards = refundDetails.reward.sub(nftRewards);
    const withdrawAmount = refundDetails.principal.add(coinPoolRewards).add(1);
    const coinPoolPendingRewards = await contracts.bendStakeManager.pendingRewards(0);

    const coinPoolSigner = await ethers.getSigner(contracts.bendCoinPool.address);
    await expect(
      contracts.bendStakeManager.connect(coinPoolSigner).withdrawApeCoin(withdrawAmount)
    ).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [refundDetails.principal.add(coinPoolRewards).add(coinPoolPendingRewards), nftRewards]
    );
  });

  it("withdrawApeCoin: refund & coin pool rewards & coin pool staked ape coin", async () => {
    const refundDetails = await contracts.bendStakeManager.refundOfDetails(contracts.bakc.address);
    const nftRewards = await calculateNftRewards(refundDetails.reward, contracts.bakcStrategy);
    const coinPoolRewards = refundDetails.reward.sub(nftRewards);
    const coinPoolPendingRewards = await contracts.bendStakeManager.pendingRewards(0);

    const withdrawAmount = refundDetails.principal.add(coinPoolRewards).add(coinPoolPendingRewards).add(1);

    const coinPoolSigner = await ethers.getSigner(contracts.bendCoinPool.address);
    await expect(
      contracts.bendStakeManager.connect(coinPoolSigner).withdrawApeCoin(withdrawAmount)
    ).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.bendNftPool.address],
      [withdrawAmount, nftRewards]
    );
  });
});
