import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "../setup";
import { advanceHours, makeBN18, mintNft, randomUint } from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, constants } from "ethers";
import { ApeCoinStaking, MintableERC721 } from "../../../typechain-types";

/* eslint-disable @typescript-eslint/no-var-requires */
const _ = require("lodash");
/* eslint-disable no-unused-expressions */
/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable node/no-unsupported-features/es-builtins */
makeSuite("NftVault", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let lastRevert: string;
  let staker: SignerWithAddress;
  let owner: SignerWithAddress;
  let recipient: SignerWithAddress;
  let baycTokenIds: number[];
  let maycTokenIds: number[];
  let bakcTokenIds: number[];

  before(async () => {
    staker = env.admin;
    owner = env.accounts[1];
    recipient = env.accounts[2];
    baycTokenIds = [0, 1, 2, 3, 4, 5];
    maycTokenIds = [6, 7, 8, 9, 10];
    bakcTokenIds = [10, 11, 12, 13, 14];

    await mintNft(owner, contracts.bayc, baycTokenIds);
    await mintNft(owner, contracts.mayc, maycTokenIds);
    await mintNft(owner, contracts.bakc, bakcTokenIds);
    await contracts.wrapApeCoin.connect(staker).approve(contracts.nftVault.address, constants.MaxUint256);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.nftVault.address, true);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.nftVault.address, true);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.nftVault.address, true);

    await contracts.bayc.connect(owner).setApprovalForAll(contracts.apeStaking.address, true);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.apeStaking.address, true);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.apeStaking.address, true);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("onlyAuthorized: reverts", async () => {
    await expect(
      contracts.nftVault.connect(owner).depositNft(contracts.bayc.address, baycTokenIds, staker.address)
    ).revertedWith("StNft: caller is not authorized");
    await expect(contracts.nftVault.connect(owner).withdrawNft(contracts.bayc.address, baycTokenIds)).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(owner).withdrawRefunds(contracts.bayc.address)).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(staker).stakeBaycPool([], [])).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(staker).stakeMaycPool([], [])).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(staker).stakeBakcPool([], [])).revertedWith(
      "StNft: caller is not authorized"
    );

    await expect(contracts.nftVault.connect(staker).unstakeBaycPool([], [], constants.AddressZero)).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(staker).unstakeMaycPool([], [], constants.AddressZero)).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(staker).unstakeBakcPool([], [], constants.AddressZero)).revertedWith(
      "StNft: caller is not authorized"
    );

    await expect(contracts.nftVault.connect(staker).claimBaycPool([], constants.AddressZero)).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(staker).claimMaycPool([], constants.AddressZero)).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(staker).claimBakcPool([], constants.AddressZero)).revertedWith(
      "StNft: caller is not authorized"
    );

    await contracts.nftVault.connect(env.admin).authorise(owner.address, true);
    await contracts.nftVault.connect(env.admin).authorise(staker.address, true);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("onlyApe: reverts", async () => {
    await expect(contracts.nftVault.depositNft(constants.AddressZero, [], constants.AddressZero)).revertedWith(
      "NftVault: not ape"
    );
  });

  const expectDepositNft = async (
    nft: MintableERC721,
    tokenIds: number[],
    staker: SignerWithAddress,
    owner: SignerWithAddress
  ) => {
    await expect(contracts.nftVault.connect(owner).depositNft(nft.address, tokenIds, staker.address)).not.reverted;
    for (let id of tokenIds) {
      expect(await contracts.nftVault.stakerOf(nft.address, id)).eq(staker.address);
      expect(await contracts.nftVault.ownerOf(nft.address, id)).eq(owner.address);
      expect(await nft.ownerOf(id)).eq(contracts.nftVault.address);
    }
  };

  it("depositNft: revert when deposit bayc already staked in official", async () => {
    const tokenIds = [baycTokenIds[0]];
    const amounts = [makeBN18(randomUint(1, 10094))];
    await contracts.apeStaking.connect(owner).deposit(1, tokenIds, amounts, { value: amounts[0] });
    await expect(
      contracts.nftVault.connect(owner).depositNft(contracts.bayc.address, tokenIds, staker.address)
    ).revertedWith("nftVault: nft already staked");
  });

  it("depositNft: revert when deposit mayc already staked in official", async () => {
    const tokenIds = [maycTokenIds[0]];
    const amounts = [makeBN18(randomUint(1, 2042))];
    await contracts.apeStaking.connect(owner).deposit(2, tokenIds, amounts, { value: amounts[0] });
    await expect(
      contracts.nftVault.connect(owner).depositNft(contracts.mayc.address, tokenIds, staker.address)
    ).revertedWith("nftVault: nft already staked");
  });

  it("depositNft: revert when deposit bakc already staked in official", async () => {
    const tokenIds = [bakcTokenIds[0]];
    const amounts = [makeBN18(randomUint(1, 856))];
    await contracts.apeStaking.connect(owner).deposit(3, tokenIds, amounts, { value: amounts[0] });

    await expect(
      contracts.nftVault.connect(owner).depositNft(contracts.bakc.address, tokenIds, staker.address)
    ).revertedWith("nftVault: nft already staked");
  });

  it("depositNft", async () => {
    await expectDepositNft(contracts.bayc, baycTokenIds, staker, owner);
    await expectDepositNft(contracts.mayc, maycTokenIds, staker, owner);
    await expectDepositNft(contracts.bakc, bakcTokenIds, staker, owner);
    lastRevert = "depositNft";
    await snapshots.capture(lastRevert);
  });

  it("setDelegateCash", async () => {
    {
      await contracts.nftVault
        .connect(owner)
        .setDelegateCash(owner.address, contracts.bayc.address, baycTokenIds, true);
      const delegates = await contracts.nftVault.getDelegateCashForToken(contracts.bayc.address, baycTokenIds);
      expect(delegates.length).eq(baycTokenIds.length);
      for (let i = 0; i < delegates.length; i++) {
        expect(delegates[i].length).eq(1);
        expect(delegates[i][0]).eq(owner.address);
      }
    }

    await contracts.nftVault.connect(owner).setDelegateCash(owner.address, contracts.bayc.address, baycTokenIds, false);
    const delegates = await contracts.nftVault.getDelegateCashForToken(contracts.bayc.address, baycTokenIds);
    expect(delegates.length).eq(baycTokenIds.length);
    for (let i = 0; i < delegates.length; i++) {
      expect(delegates[i].length).eq(0);
    }

    lastRevert = "depositNft";
  });

  it("setDelegateCashV2", async () => {
    {
      await contracts.nftVault
        .connect(owner)
        .setDelegateCashV2(owner.address, contracts.bayc.address, baycTokenIds, true);
      const delegates = await contracts.nftVault.getDelegateCashForTokenV2(contracts.bayc.address, baycTokenIds);
      expect(delegates.length).eq(baycTokenIds.length);
      for (let i = 0; i < delegates.length; i++) {
        expect(delegates[i].length).eq(1);
        expect(delegates[i][0]).eq(owner.address);
      }
    }

    await contracts.nftVault
      .connect(owner)
      .setDelegateCashV2(owner.address, contracts.bayc.address, baycTokenIds, false);
    const delegates = await contracts.nftVault.getDelegateCashForTokenV2(contracts.bayc.address, baycTokenIds);
    expect(delegates.length).eq(baycTokenIds.length);
    for (let i = 0; i < delegates.length; i++) {
      expect(delegates[i].length).eq(0);
    }

    lastRevert = "depositNft";
  });

  it("stakeBaycPool", async () => {
    let tokenIds = [];
    let amounts = [];
    let stakeAmount = constants.Zero;
    for (let [i, id] of baycTokenIds.entries()) {
      let amount = makeBN18(randomUint(1, 10094));
      tokenIds[i] = id;
      amounts[i] = amount;
      stakeAmount = stakeAmount.add(amount);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.false;
    }
    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(0);

    let poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    await expect(contracts.nftVault.connect(staker).stakeBaycPool(tokenIds, amounts)).changeTokenBalances(
      contracts.wrapApeCoin,
      [staker.address, contracts.nftVault.address],
      [constants.Zero.sub(stakeAmount), constants.Zero]
    );

    poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(stakeAmount);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    for (let i = 0; i < tokenIds.length; i++) {
      const position = await contracts.apeStaking.nftPosition(1, tokenIds[i]);
      expect(position.stakedAmount).eq(amounts[i]);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bayc.ownerOf(tokenIds[i])).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, tokenIds[i])).be.true;
    }
    const stakingAmount = await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address);
    expect(stakingAmount).eq(tokenIds.length);

    let ids = [];
    for (let i = 0; i < stakingAmount.toNumber(); i++) {
      ids.push((await contracts.nftVault.stakingNftIdByIndex(contracts.bayc.address, staker.address, i)).toNumber());
    }
    expect(_.sortBy(baycTokenIds)).to.deep.eq(_.sortBy(ids));
    lastRevert = "stakeBaycPool";
    await snapshots.capture(lastRevert);
  });

  it("claimBaycPool", async () => {
    await advanceHours(100);
    let rewardAmount = constants.Zero;
    let rewardMap = new Map<number, BigNumber>();
    for (let id of baycTokenIds) {
      let amount = await contracts.apeStaking.pendingRewards(1, id);
      rewardMap.set(id, amount);
      rewardAmount = rewardAmount.add(amount);
    }
    await expect(contracts.nftVault.connect(staker).claimBaycPool(baycTokenIds, recipient.address)).changeTokenBalances(
      contracts.wrapApeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [rewardAmount, constants.Zero, constants.Zero, constants.Zero]
    );
    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let id of baycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(1, id);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.rewardsDebt).eq(rewardMap.get(id)?.mul(constants.WeiPerEther));
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);
  });

  it("unstakeBaycPool: unstake fully", async () => {
    await advanceHours(100);

    let tokenIds = [];
    let amounts = [];
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    for (let [i, id] of baycTokenIds.entries()) {
      let amount = (await contracts.apeStaking.nftPosition(1, id)).stakedAmount;
      let reward = await contracts.apeStaking.pendingRewards(1, id);
      tokenIds[i] = id;
      amounts[i] = amount;
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);

    await expect(
      contracts.nftVault.connect(staker).unstakeBaycPool(tokenIds, amounts, recipient.address)
    ).changeTokenBalances(
      contracts.wrapApeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [unstakeAmount.add(rewardAmount), constants.Zero, constants.Zero, constants.Zero]
    );
    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let id of baycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(1, id);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.false;
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(0);
  });

  it("unstakeBaycPool: unstake partially", async () => {
    await advanceHours(100);

    let tokenIds = [];
    let amounts = [];
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    let unstakeNftAmount = 0;
    let stakingNftIds = [];
    const withdrawAmount = new Map<number, BigNumber>();
    const positions = new Map<number, any>();

    for (let [i, id] of baycTokenIds.entries()) {
      const posision = await contracts.apeStaking.nftPosition(1, id);
      let amount = posision.stakedAmount;
      let reward;
      if (i % 2 === 1) {
        amount = amount.div(2);
        reward = constants.Zero;
        stakingNftIds.push(id);
      } else {
        unstakeNftAmount++;
        reward = await contracts.apeStaking.pendingRewards(1, id);
      }
      withdrawAmount.set(id, amount);
      tokenIds[i] = id;
      amounts[i] = amount;
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
      positions.set(id, posision);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);

    await expect(
      contracts.nftVault.connect(staker).unstakeBaycPool(tokenIds, amounts, recipient.address)
    ).changeTokenBalances(
      contracts.wrapApeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [unstakeAmount.add(rewardAmount), constants.Zero, constants.Zero, constants.Zero]
    );

    const accumulatedRewardsPerShare = (await contracts.apeStaking.pools(1)).accumulatedRewardsPerShare;

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let id of baycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(1, id);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      const prePosition = positions.get(id);
      if (withdrawAmount.get(id)?.eq(prePosition.stakedAmount)) {
        expect(position.stakedAmount).eq(constants.Zero);
        expect(position.rewardsDebt).eq(constants.Zero);
        expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.false;
      } else {
        expect(position.stakedAmount).eq(prePosition.stakedAmount.sub(withdrawAmount.get(id)));
        expect(position.rewardsDebt).eq(
          constants.Zero.sub((withdrawAmount.get(id) as BigNumber).mul(accumulatedRewardsPerShare))
        );
        expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
      }
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(
      baycTokenIds.length - unstakeNftAmount
    );
    let ids = [];
    for (let i = 0; i < baycTokenIds.length - unstakeNftAmount; i++) {
      ids.push((await contracts.nftVault.stakingNftIdByIndex(contracts.bayc.address, staker.address, i)).toNumber());
    }
    expect(_.sortBy(stakingNftIds)).to.deep.eq(_.sortBy(ids));
  });

  it("withdrawNft: withdraw nonpaired bayc", async () => {
    await advanceHours(100);
    const preRefund = await contracts.nftVault.refundOf(contracts.bayc.address, staker.address);
    expect(preRefund.principal).eq(constants.Zero);
    expect(preRefund.reward).eq(constants.Zero);
    let principal = constants.Zero;
    let reward = constants.Zero;
    for (const id of baycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(1, id);
      principal = principal.add(position.stakedAmount);
      reward = reward.add(await contracts.apeStaking.pendingRewards(1, id));
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }
    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);

    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.bayc.address, baycTokenIds)
    ).changeTokenBalances(contracts.wrapApeCoin, [contracts.nftVault.address], [principal.add(reward)]);

    for (const id of baycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(1, id);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bayc.ownerOf(id)).eq(owner.address);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.false;
    }
    const refund = await contracts.nftVault.refundOf(contracts.bayc.address, staker.address);
    expect(refund.principal).eq(principal);
    expect(refund.reward).eq(reward);
    const poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(0);
  });

  it("stakeMaycPool", async () => {
    let tokenIds = [];
    let amounts = [];
    let stakeAmount = constants.Zero;
    for (let [i, id] of maycTokenIds.entries()) {
      let amount = makeBN18(randomUint(1, 2042));
      tokenIds[i] = id;
      amounts[i] = amount;
      stakeAmount = stakeAmount.add(amount);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.false;
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(0);

    await expect(contracts.nftVault.connect(staker).stakeMaycPool(tokenIds, amounts)).changeTokenBalances(
      contracts.wrapApeCoin,
      [staker.address, contracts.nftVault.address],
      [constants.Zero.sub(stakeAmount), constants.Zero]
    );

    const position = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(position.stakedAmount).eq(stakeAmount);
    expect(position.rewardsDebt).eq(constants.Zero);

    for (let i = 0; i < tokenIds.length; i++) {
      const position = await contracts.apeStaking.nftPosition(2, tokenIds[i]);
      expect(position.stakedAmount).eq(amounts[i]);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.mayc.ownerOf(tokenIds[i])).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, tokenIds[i])).be.true;
    }

    const stakingNftAmount = await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address);
    expect(stakingNftAmount).eq(tokenIds.length);

    let ids = [];
    for (let i = 0; i < stakingNftAmount.toNumber(); i++) {
      ids.push((await contracts.nftVault.stakingNftIdByIndex(contracts.mayc.address, staker.address, i)).toNumber());
    }
    expect(_.sortBy(maycTokenIds)).to.deep.eq(_.sortBy(ids));

    lastRevert = "stakeMaycPool";
    await snapshots.capture(lastRevert);
  });

  it("claimMaycPool", async () => {
    await advanceHours(100);
    let rewardAmount = constants.Zero;
    const rewardMap = new Map<number, BigNumber>();
    for (let id of maycTokenIds) {
      const amount = await contracts.apeStaking.pendingRewards(2, id);
      rewardMap.set(id, amount);
      rewardAmount = rewardAmount.add(amount);
    }
    await expect(contracts.nftVault.connect(staker).claimMaycPool(maycTokenIds, recipient.address)).changeTokenBalances(
      contracts.wrapApeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [rewardAmount, constants.Zero, constants.Zero, constants.Zero]
    );
    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let id of maycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.rewardsDebt).eq(rewardMap.get(id)?.mul(constants.WeiPerEther));
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);
  });

  it("unstakeMaycPool: unstake fully", async () => {
    await advanceHours(100);

    let tokenIds = [];
    let amounts = [];
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    for (let [i, id] of maycTokenIds.entries()) {
      let amount = (await contracts.apeStaking.nftPosition(2, id)).stakedAmount;
      let reward = await contracts.apeStaking.pendingRewards(2, id);
      tokenIds[i] = id;
      amounts[i] = amount;
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }
    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    await expect(
      contracts.nftVault.connect(staker).unstakeMaycPool(tokenIds, amounts, recipient.address)
    ).changeTokenBalances(
      contracts.wrapApeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [unstakeAmount.add(rewardAmount), constants.Zero, constants.Zero, constants.Zero]
    );

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;

    for (let id of maycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.false;
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);
    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(0);
  });

  it("unstakeMaycPool: unstake partially", async () => {
    await advanceHours(100);

    let tokenIds = [];
    let amounts = [];
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    let unstakeNftAmount = 0;
    let stakingNftIds = [];
    const withdrawAmount = new Map<number, BigNumber>();
    const positions = new Map<number, any>();
    for (let [i, id] of maycTokenIds.entries()) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      let amount = position.stakedAmount;
      let reward;
      if (i % 2 === 1) {
        amount = amount.div(2);
        reward = constants.Zero;
        stakingNftIds.push(id);
      } else {
        unstakeNftAmount++;
        reward = await contracts.apeStaking.pendingRewards(2, id);
      }
      tokenIds[i] = id;
      amounts[i] = amount;
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
      withdrawAmount.set(id, amount);
      positions.set(id, position);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    await expect(
      contracts.nftVault.connect(staker).unstakeMaycPool(tokenIds, amounts, recipient.address)
    ).changeTokenBalances(
      contracts.wrapApeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [unstakeAmount.add(rewardAmount), constants.Zero, constants.Zero, constants.Zero]
    );

    const accumulatedRewardsPerShare = (await contracts.apeStaking.pools(2)).accumulatedRewardsPerShare;

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let id of maycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      const prePosition = positions.get(id);
      if (withdrawAmount.get(id)?.eq(prePosition.stakedAmount)) {
        expect(position.stakedAmount).eq(constants.Zero);
        expect(position.rewardsDebt).eq(constants.Zero);
        expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.false;
      } else {
        expect(position.stakedAmount).eq(prePosition.stakedAmount.sub(withdrawAmount.get(id)));
        expect(position.rewardsDebt).eq(
          constants.Zero.sub((withdrawAmount.get(id) as BigNumber).mul(accumulatedRewardsPerShare))
        );
        expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
      }
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(
      maycTokenIds.length - unstakeNftAmount
    );
    let ids = [];
    for (let i = 0; i < maycTokenIds.length - unstakeNftAmount; i++) {
      ids.push((await contracts.nftVault.stakingNftIdByIndex(contracts.mayc.address, staker.address, i)).toNumber());
    }
    expect(_.sortBy(stakingNftIds)).to.deep.eq(_.sortBy(ids));
  });

  it("withdrawNft: withdraw nonpaired mayc", async () => {
    await advanceHours(100);
    const preRefund = await contracts.nftVault.refundOf(contracts.mayc.address, staker.address);
    expect(preRefund.principal).eq(constants.Zero);
    expect(preRefund.reward).eq(constants.Zero);
    let principal = constants.Zero;
    let reward = constants.Zero;
    for (const id of maycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      principal = principal.add(position.stakedAmount);
      reward = reward.add(await contracts.apeStaking.pendingRewards(2, id));
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.mayc.address, maycTokenIds)
    ).changeTokenBalances(contracts.wrapApeCoin, [contracts.nftVault.address], [principal.add(reward)]);

    for (const id of maycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.mayc.ownerOf(id)).eq(owner.address);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.false;
    }
    const refund = await contracts.nftVault.refundOf(contracts.mayc.address, staker.address);
    expect(refund.principal).eq(principal);
    expect(refund.reward).eq(reward);
    const poolPosition = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(0);
  });

  it("stakeBakcPool", async () => {
    let tokenIds = [];
    let amounts = [];
    let stakeAmount = constants.Zero;
    for (let [i, id] of bakcTokenIds.entries()) {
      let amount = makeBN18(randomUint(1, 856));
      tokenIds[i] = id;
      amounts[i] = amount;

      stakeAmount = stakeAmount.add(amount);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.false;
    }
    const prePoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(prePoolPosition.stakedAmount).eq(constants.Zero);
    expect(prePoolPosition.rewardsDebt).eq(constants.Zero);
    await expect(contracts.nftVault.connect(staker).stakeBakcPool(tokenIds, amounts)).changeTokenBalances(
      contracts.wrapApeCoin,
      [staker.address, contracts.nftVault.address],
      [constants.Zero.sub(stakeAmount), constants.Zero]
    );

    const poolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(stakeAmount);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let i = 0; i < tokenIds.length; i++) {
      const position = await contracts.apeStaking.nftPosition(3, tokenIds[i]);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.stakedAmount).eq(amounts[i]);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(tokenIds[i])).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, tokenIds[i])).be.true;
    }

    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);

    const stakingNftAmount = await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address);
    expect(stakingNftAmount).eq(tokenIds.length);

    let ids = [];
    for (let i = 0; i < stakingNftAmount.toNumber(); i++) {
      ids.push((await contracts.nftVault.stakingNftIdByIndex(contracts.bakc.address, staker.address, i)).toNumber());
    }
    expect(_.sortBy(bakcTokenIds)).to.deep.eq(_.sortBy(ids));

    lastRevert = "stakeBakcPool";
    await snapshots.capture(lastRevert);
  });

  it("claimBakcPool", async () => {
    await advanceHours(100);

    let rewardAmount = constants.Zero;
    let rewardMap = new Map<number, BigNumber>();

    for (let id of bakcTokenIds) {
      const amount = await contracts.apeStaking.pendingRewards(3, id);
      rewardMap.set(id, amount);
      rewardAmount = rewardAmount.add(amount);
    }

    await expect(contracts.nftVault.connect(staker).claimBakcPool(bakcTokenIds, recipient.address)).changeTokenBalances(
      contracts.wrapApeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [rewardAmount, constants.Zero, constants.Zero, constants.Zero]
    );

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let id of bakcTokenIds) {
      const position = await contracts.apeStaking.nftPosition(3, id);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.rewardsDebt).eq(rewardMap.get(id)?.mul(constants.WeiPerEther));
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);
  });

  it("unstakeBakcPool: unstake fully", async () => {
    await advanceHours(100);
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    let amounts = [];
    for (let id of bakcTokenIds) {
      const stakedAmount = (await contracts.apeStaking.nftPosition(3, id)).stakedAmount;
      const reward = await contracts.apeStaking.pendingRewards(3, id);
      rewardAmount = rewardAmount.add(reward);
      unstakeAmount = unstakeAmount.add(stakedAmount);
      amounts.push(stakedAmount);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(bakcTokenIds.length);

    await expect(
      contracts.nftVault.connect(staker).unstakeBakcPool(bakcTokenIds, amounts, recipient.address)
    ).changeTokenBalances(
      contracts.wrapApeCoin,
      [staker.address, contracts.nftVault.address, recipient.address],
      [constants.Zero, constants.Zero, unstakeAmount.add(rewardAmount)]
    );

    const poolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let bakcId of bakcTokenIds) {
      const position = await contracts.apeStaking.nftPosition(3, bakcId);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(bakcId)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, bakcId)).be.false;
    }

    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(0);
  });

  it("withdrawNft: withdraw bayc", async () => {
    await advanceHours(100);
    const preRefund = await contracts.nftVault.refundOf(contracts.bayc.address, staker.address);
    expect(preRefund.principal).eq(constants.Zero);
    expect(preRefund.reward).eq(constants.Zero);
    let baycPrincipal = constants.Zero;
    let baycReward = constants.Zero;

    for (const id of baycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(1, id);
      baycPrincipal = baycPrincipal.add(position.stakedAmount);
      baycReward = baycReward.add(await contracts.apeStaking.pendingRewards(1, id));
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);

    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.bayc.address, baycTokenIds)
    ).changeTokenBalances(contracts.wrapApeCoin, [contracts.nftVault.address], [baycPrincipal.add(baycReward)]);

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(0);

    for (const id of baycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(1, id);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bayc.ownerOf(id)).eq(owner.address);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.false;
    }
    const refund = await contracts.nftVault.refundOf(contracts.bayc.address, staker.address);
    expect(refund.principal).eq(baycPrincipal);
    expect(refund.reward).eq(baycReward);
    const poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);
  });

  it("withdrawNft: withdraw mayc", async () => {
    await advanceHours(100);
    const preRefund = await contracts.nftVault.refundOf(contracts.mayc.address, staker.address);
    expect(preRefund.principal).eq(constants.Zero);
    expect(preRefund.reward).eq(constants.Zero);
    let maycPrincipal = constants.Zero;
    let maycReward = constants.Zero;

    for (const id of maycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      maycPrincipal = maycPrincipal.add(position.stakedAmount);
      maycReward = maycReward.add(await contracts.apeStaking.pendingRewards(2, id));
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.mayc.address, maycTokenIds)
    ).changeTokenBalances(contracts.wrapApeCoin, [contracts.nftVault.address], [maycPrincipal.add(maycReward)]);

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(0);

    for (const id of maycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.mayc.ownerOf(id)).eq(owner.address);
    }
    const refund = await contracts.nftVault.refundOf(contracts.mayc.address, staker.address);
    expect(refund.principal).eq(maycPrincipal);
    expect(refund.reward).eq(maycReward);
    const poolPosition = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);
  });

  it("withdrawNft: withdraw bakc", async () => {
    await advanceHours(100);
    const preRefund = await contracts.nftVault.refundOf(contracts.mayc.address, staker.address);
    expect(preRefund.principal).eq(constants.Zero);
    expect(preRefund.reward).eq(constants.Zero);
    let bakcPrincipal = constants.Zero;
    let bakcReward = constants.Zero;

    for (const id of bakcTokenIds) {
      const position = await contracts.apeStaking.nftPosition(3, id);
      bakcPrincipal = bakcPrincipal.add(position.stakedAmount);
      bakcReward = bakcReward.add(await contracts.apeStaking.pendingRewards(3, id));

      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(bakcTokenIds.length);
    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);
    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    const preBakcPoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.bakc.address, bakcTokenIds)
    ).changeTokenBalances(contracts.wrapApeCoin, [contracts.nftVault.address], [bakcPrincipal.add(bakcReward)]);

    let refund = await contracts.nftVault.refundOf(contracts.bayc.address, staker.address);
    expect(refund.principal).eq(constants.Zero);
    expect(refund.reward).eq(constants.Zero);

    refund = await contracts.nftVault.refundOf(contracts.mayc.address, staker.address);
    expect(refund.principal).eq(constants.Zero);
    expect(refund.reward).eq(constants.Zero);

    for (const id of bakcTokenIds) {
      const position = await contracts.apeStaking.nftPosition(3, id);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(id)).eq(owner.address);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.false;
    }
    const bakcRefund = await contracts.nftVault.refundOf(contracts.bakc.address, staker.address);
    expect(bakcRefund.principal).eq(bakcPrincipal);
    expect(bakcRefund.reward).eq(bakcReward);

    const bakcPoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(bakcPoolPosition.stakedAmount).eq(preBakcPoolPosition.stakedAmount.sub(bakcPrincipal));
    expect(bakcPoolPosition.rewardsDebt).eq(constants.Zero);

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(0);
    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);
    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);
  });
});
