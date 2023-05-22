import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "../setup";
import { advanceHours, makeBN18, mintNft, randomUint, shuffledSubarray } from "../utils";
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
    await contracts.apeCoin.connect(staker).approve(contracts.nftVault.address, constants.MaxUint256);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.nftVault.address, true);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.nftVault.address, true);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.nftVault.address, true);

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
    await expect(contracts.nftVault.connect(staker).stakeBaycPool([])).revertedWith("StNft: caller is not authorized");
    await expect(contracts.nftVault.connect(staker).stakeMaycPool([])).revertedWith("StNft: caller is not authorized");
    await expect(contracts.nftVault.connect(staker).stakeBakcPool([], [])).revertedWith(
      "StNft: caller is not authorized"
    );

    await expect(contracts.nftVault.connect(staker).unstakeBaycPool([], constants.AddressZero)).revertedWith(
      "StNft: caller is not authorized"
    );
    await expect(contracts.nftVault.connect(staker).unstakeMaycPool([], constants.AddressZero)).revertedWith(
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
    await expect(contracts.nftVault.connect(staker).claimBakcPool([], [], constants.AddressZero)).revertedWith(
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

  it("depositNft", async () => {
    await expectDepositNft(contracts.bayc, baycTokenIds, staker, owner);
    await expectDepositNft(contracts.mayc, maycTokenIds, staker, owner);
    await expectDepositNft(contracts.bakc, bakcTokenIds, staker, owner);
    lastRevert = "depositNft";
    await snapshots.capture(lastRevert);
  });

  it("stakeBaycPool", async () => {
    let nfts = [];
    let stakeAmount = constants.Zero;
    for (let [i, id] of baycTokenIds.entries()) {
      let amount = makeBN18(randomUint(1, 10094));
      nfts[i] = {
        tokenId: id,
        amount,
      };
      stakeAmount = stakeAmount.add(amount);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.false;
    }
    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(0);

    let poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    await expect(contracts.nftVault.connect(staker).stakeBaycPool(nfts)).changeTokenBalances(
      contracts.apeCoin,
      [staker.address, contracts.nftVault.address, contracts.apeStaking.address],
      [constants.Zero.sub(stakeAmount), constants.Zero, stakeAmount]
    );

    poolPosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(stakeAmount);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    for (let nft of nfts) {
      const position = await contracts.apeStaking.nftPosition(1, nft.tokenId);
      expect(position.stakedAmount).eq(nft.amount);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bayc.ownerOf(nft.tokenId)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, nft.tokenId)).be.true;
    }
    const stakingAmount = await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address);
    expect(stakingAmount).eq(nfts.length);

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
      let amount = await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id);
      rewardMap.set(id, amount);
      rewardAmount = rewardAmount.add(amount);
    }
    await expect(contracts.nftVault.connect(staker).claimBaycPool(baycTokenIds, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
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

    let nfts = [];
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    for (let [i, id] of baycTokenIds.entries()) {
      let amount = (await contracts.apeStaking.nftPosition(1, id)).stakedAmount;
      let reward = await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id);
      nfts[i] = {
        tokenId: id,
        amount,
      };
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);

    await expect(contracts.nftVault.connect(staker).unstakeBaycPool(nfts, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
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

    let nfts = [];
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
        reward = await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id);
      }
      withdrawAmount.set(id, amount);
      nfts[i] = {
        tokenId: id,
        amount,
      };
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
      positions.set(id, posision);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);

    await expect(contracts.nftVault.connect(staker).unstakeBaycPool(nfts, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
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
      reward = reward.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }
    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);

    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.bayc.address, baycTokenIds)
    ).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.nftVault.address],
      [constants.Zero.sub(principal).sub(reward), principal.add(reward)]
    );

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
    let nfts = [];
    let stakeAmount = constants.Zero;
    for (let [i, id] of maycTokenIds.entries()) {
      let amount = makeBN18(randomUint(1, 2042));
      nfts[i] = {
        tokenId: id,
        amount,
      };
      stakeAmount = stakeAmount.add(amount);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.false;
    }
    const poolPosition = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(0);

    await expect(contracts.nftVault.connect(staker).stakeMaycPool(nfts)).changeTokenBalances(
      contracts.apeCoin,
      [staker.address, contracts.nftVault.address, contracts.apeStaking.address],
      [constants.Zero.sub(stakeAmount), constants.Zero, stakeAmount]
    );

    const position = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(position.stakedAmount).eq(stakeAmount);
    expect(position.rewardsDebt).eq(constants.Zero);

    for (let nft of nfts) {
      const position = await contracts.apeStaking.nftPosition(2, nft.tokenId);
      expect(position.stakedAmount).eq(nft.amount);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.mayc.ownerOf(nft.tokenId)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, nft.tokenId)).be.true;
    }

    const stakingNftAmount = await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address);
    expect(stakingNftAmount).eq(nfts.length);

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
      const amount = await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id);
      rewardMap.set(id, amount);
      rewardAmount = rewardAmount.add(amount);
    }
    await expect(contracts.nftVault.connect(staker).claimMaycPool(maycTokenIds, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
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

    let nfts = [];
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    for (let [i, id] of maycTokenIds.entries()) {
      let amount = (await contracts.apeStaking.nftPosition(2, id)).stakedAmount;
      let reward = await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id);
      nfts[i] = {
        tokenId: id,
        amount,
      };
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }
    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    await expect(contracts.nftVault.connect(staker).unstakeMaycPool(nfts, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
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

    let nfts = [];
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
        reward = await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id);
      }
      nfts[i] = {
        tokenId: id,
        amount,
      };
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
      withdrawAmount.set(id, amount);
      positions.set(id, position);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    await expect(contracts.nftVault.connect(staker).unstakeMaycPool(nfts, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
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
      reward = reward.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.mayc.address, maycTokenIds)
    ).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.nftVault.address],
      [constants.Zero.sub(principal).sub(reward), principal.add(reward)]
    );

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
    let stakeAmount = constants.Zero;
    let baycNfts = [];
    let maycNfts = [];
    let baycIndex = 0;
    let maycIndex = 0;
    for (let [i, id] of bakcTokenIds.entries()) {
      let amount = makeBN18(randomUint(1, 856));
      if (i % 2 === 1) {
        baycNfts[baycIndex] = {
          mainTokenId: baycTokenIds[baycIndex],
          bakcTokenId: id,
          amount,
        };
        baycIndex++;
      } else {
        maycNfts[maycIndex] = {
          mainTokenId: maycTokenIds[maycIndex],
          bakcTokenId: id,
          amount,
        };
        maycIndex++;
      }

      stakeAmount = stakeAmount.add(amount);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.false;
    }
    const prePoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(prePoolPosition.stakedAmount).eq(constants.Zero);
    expect(prePoolPosition.rewardsDebt).eq(constants.Zero);
    await expect(contracts.nftVault.connect(staker).stakeBakcPool(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [staker.address, contracts.nftVault.address, contracts.apeStaking.address],
      [constants.Zero.sub(stakeAmount), constants.Zero, stakeAmount]
    );

    const poolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(stakeAmount);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let nft of baycNfts) {
      const position = await contracts.apeStaking.nftPosition(3, nft.bakcTokenId);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.stakedAmount).eq(nft.amount);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(nft.bakcTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.bayc.ownerOf(nft.mainTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, nft.bakcTokenId)).be.true;
    }

    for (let nft of maycNfts) {
      const position = await contracts.apeStaking.nftPosition(3, nft.bakcTokenId);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.stakedAmount).eq(nft.amount);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(nft.bakcTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.mayc.ownerOf(nft.mainTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, nft.bakcTokenId)).be.true;
    }

    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);

    const stakingNftAmount = await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address);
    expect(stakingNftAmount).eq(baycNfts.length + maycNfts.length);

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
    let baycNfts = [];
    let maycNfts = [];
    let baycIndex = 0;
    let maycIndex = 0;

    for (let id of bakcTokenIds) {
      let pairStauts = await contracts.apeStaking.bakcToMain(id, 1);
      if (pairStauts.isPaired) {
        baycNfts[baycIndex] = {
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
        };
        baycIndex++;
      } else {
        pairStauts = await contracts.apeStaking.bakcToMain(id, 2);
        maycNfts[maycIndex] = {
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
        };
        maycIndex++;
      }
      const amount = await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id);
      rewardMap.set(id, amount);
      rewardAmount = rewardAmount.add(amount);
    }

    await expect(
      contracts.nftVault.connect(staker).claimBakcPool(baycNfts, maycNfts, recipient.address)
    ).changeTokenBalances(
      contracts.apeCoin,
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
    let baycNfts = [];
    let maycNfts = [];
    let baycIndex = 0;
    let maycIndex = 0;
    for (let id of bakcTokenIds) {
      const stakedAmount = (await contracts.apeStaking.nftPosition(3, id)).stakedAmount;
      const reward = await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id);
      const pairStauts = await contracts.apeStaking.bakcToMain(id, 1);
      if (pairStauts.isPaired) {
        baycNfts[baycIndex] = {
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
          amount: stakedAmount,
          isUncommit: true,
        };
        baycIndex++;
      } else {
        const pairStauts = await contracts.apeStaking.bakcToMain(id, 2);
        maycNfts[maycIndex] = {
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
          amount: stakedAmount,
          isUncommit: true,
        };
        maycIndex++;
      }
      rewardAmount = rewardAmount.add(reward);
      unstakeAmount = unstakeAmount.add(stakedAmount);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(bakcTokenIds.length);

    await expect(
      contracts.nftVault.connect(staker).unstakeBakcPool(baycNfts, maycNfts, recipient.address)
    ).changeTokenBalances(
      contracts.apeCoin,
      [staker.address, contracts.nftVault.address, contracts.apeStaking.address, recipient.address],
      [
        constants.Zero,
        constants.Zero,
        constants.Zero.sub(unstakeAmount).sub(rewardAmount),
        unstakeAmount.add(rewardAmount),
      ]
    );

    const poolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(constants.Zero);
    expect(poolPosition.rewardsDebt).eq(constants.Zero);

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let nft of baycNfts) {
      const position = await contracts.apeStaking.nftPosition(3, nft.bakcTokenId);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(nft.bakcTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.bayc.ownerOf(nft.mainTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, nft.bakcTokenId)).be.false;
    }

    for (let nft of maycNfts) {
      const position = await contracts.apeStaking.nftPosition(3, nft.bakcTokenId);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(nft.bakcTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.mayc.ownerOf(nft.mainTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, nft.bakcTokenId)).be.false;
    }

    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(0);
  });

  it("unstakeBakcPool: unstake partially", async () => {
    await advanceHours(100);
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    let baycNfts = [];
    let maycNfts = [];
    let baycIndex = 0;
    let maycIndex = 0;
    const unstakedAmountMap = new Map<number, BigNumber>();
    const positions = new Map<number, any>();
    let unstakeNftAmount = 0;
    let stakingNftIds = [];
    for (let [i, id] of bakcTokenIds.entries()) {
      const position = await contracts.apeStaking.nftPosition(3, id);
      positions.set(id, position);
      let stakedAmount = position.stakedAmount;
      let reward;
      let fullUnstake = false;
      if (i % 2 === 1) {
        stakingNftIds.push(id);
        stakedAmount = stakedAmount.div(2);
        reward = constants.Zero;
      } else {
        fullUnstake = true;
        unstakeNftAmount++;
        reward = await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id);
      }
      const pairStauts = await contracts.apeStaking.bakcToMain(id, 1);
      if (pairStauts.isPaired) {
        baycNfts[baycIndex] = {
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
          amount: stakedAmount,
          isUncommit: fullUnstake,
        };
        baycIndex++;
      } else {
        const pairStauts = await contracts.apeStaking.bakcToMain(id, 2);
        maycNfts[maycIndex] = {
          mainTokenId: pairStauts.tokenId,
          bakcTokenId: id,
          amount: stakedAmount,
          isUncommit: fullUnstake,
        };
        maycIndex++;
      }
      rewardAmount = rewardAmount.add(reward);
      unstakeAmount = unstakeAmount.add(stakedAmount);
      unstakedAmountMap.set(id, stakedAmount);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(bakcTokenIds.length);

    const prePoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    await expect(
      contracts.nftVault.connect(staker).unstakeBakcPool(baycNfts, maycNfts, recipient.address)
    ).changeTokenBalances(
      contracts.apeCoin,
      [staker.address, contracts.nftVault.address, contracts.apeStaking.address, recipient.address],
      [
        constants.Zero,
        constants.Zero,
        constants.Zero.sub(unstakeAmount).sub(rewardAmount),
        unstakeAmount.add(rewardAmount),
      ]
    );
    const accumulatedRewardsPerShare = (await contracts.apeStaking.pools(3)).accumulatedRewardsPerShare;
    const poolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(poolPosition.stakedAmount).eq(prePoolPosition.stakedAmount.sub(unstakeAmount));

    let allPositionStakedAmount = constants.Zero;
    let allPositionRewardsDebt = constants.Zero;
    for (let nft of baycNfts) {
      const position = await contracts.apeStaking.nftPosition(3, nft.bakcTokenId);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(await contracts.bakc.ownerOf(nft.bakcTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.bayc.ownerOf(nft.mainTokenId)).eq(contracts.nftVault.address);

      const prePosition = positions.get(nft.bakcTokenId);
      if (unstakedAmountMap.get(nft.bakcTokenId)?.eq(prePosition.stakedAmount)) {
        expect(position.stakedAmount).eq(constants.Zero);
        expect(position.rewardsDebt).eq(constants.Zero);
        expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, nft.bakcTokenId)).be.false;
      } else {
        expect(position.stakedAmount).eq(prePosition.stakedAmount.sub(unstakedAmountMap.get(nft.bakcTokenId)));
        expect(position.rewardsDebt).eq(
          constants.Zero.sub((unstakedAmountMap.get(nft.bakcTokenId) as BigNumber).mul(accumulatedRewardsPerShare))
        );
        expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, nft.bakcTokenId)).be.true;
      }
    }

    for (let nft of maycNfts) {
      const position = await contracts.apeStaking.nftPosition(3, nft.bakcTokenId);
      allPositionStakedAmount = allPositionStakedAmount.add(position.stakedAmount);
      allPositionRewardsDebt = allPositionRewardsDebt.add(position.rewardsDebt);
      expect(await contracts.bakc.ownerOf(nft.bakcTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.mayc.ownerOf(nft.mainTokenId)).eq(contracts.nftVault.address);
      const prePosition = positions.get(nft.bakcTokenId);
      if (unstakedAmountMap.get(nft.bakcTokenId)?.eq(prePosition.stakedAmount)) {
        expect(position.stakedAmount).eq(constants.Zero);
        expect(position.rewardsDebt).eq(constants.Zero);
        expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, nft.bakcTokenId)).be.false;
      } else {
        expect(position.stakedAmount).eq(prePosition.stakedAmount.sub(unstakedAmountMap.get(nft.bakcTokenId)));
        expect(position.rewardsDebt).eq(
          constants.Zero.sub((unstakedAmountMap.get(nft.bakcTokenId) as BigNumber).mul(accumulatedRewardsPerShare))
        );
        expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, nft.bakcTokenId)).be.true;
      }
    }
    expect(poolPosition.stakedAmount).eq(allPositionStakedAmount);
    expect(poolPosition.rewardsDebt).eq(allPositionRewardsDebt);

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(
      bakcTokenIds.length - unstakeNftAmount
    );
    let ids = [];
    for (let i = 0; i < bakcTokenIds.length - unstakeNftAmount; i++) {
      ids.push((await contracts.nftVault.stakingNftIdByIndex(contracts.bakc.address, staker.address, i)).toNumber());
    }
    expect(_.sortBy(stakingNftIds)).to.deep.eq(_.sortBy(ids));
  });

  it("withdrawNft: withdraw paired and nonpaired bayc", async () => {
    await advanceHours(100);
    const preRefund = await contracts.nftVault.refundOf(contracts.bayc.address, staker.address);
    expect(preRefund.principal).eq(constants.Zero);
    expect(preRefund.reward).eq(constants.Zero);
    let baycPrincipal = constants.Zero;
    let baycReward = constants.Zero;
    let bakcPrincipal = constants.Zero;
    let bakcReward = constants.Zero;
    let pairedBakcTokenIds = [];

    for (const id of baycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(1, id);
      baycPrincipal = baycPrincipal.add(position.stakedAmount);
      baycReward = baycReward.add(await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id));
      const pairStatus = await contracts.apeStaking.mainToBakc(1, id);
      if (pairStatus.isPaired) {
        const bakcPosition = await contracts.apeStaking.nftPosition(3, pairStatus.tokenId);
        bakcPrincipal = bakcPrincipal.add(bakcPosition.stakedAmount);
        bakcReward = bakcReward.add(
          await contracts.apeStaking.pendingRewards(3, constants.AddressZero, pairStatus.tokenId)
        );
        pairedBakcTokenIds.push(pairStatus.tokenId);
        expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, pairStatus.tokenId)).be.true;
      }
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }

    const bakcStakingNftAmount = await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address);

    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);

    const preBakcPoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.bayc.address, baycTokenIds)
    ).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.nftVault.address],
      [
        constants.Zero.sub(baycPrincipal).sub(baycReward).sub(bakcPrincipal).sub(bakcReward),
        baycPrincipal.add(baycReward).add(bakcPrincipal).add(bakcReward),
      ]
    );

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

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(
      bakcStakingNftAmount.sub(pairedBakcTokenIds.length)
    );

    for (const id of pairedBakcTokenIds) {
      const position = await contracts.apeStaking.nftPosition(3, id);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(id)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.false;
    }
    const bakcRefund = await contracts.nftVault.refundOf(contracts.bakc.address, staker.address);
    expect(bakcRefund.principal).eq(bakcPrincipal);
    expect(bakcRefund.reward).eq(bakcReward);

    const bakcPoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(bakcPoolPosition.stakedAmount).eq(preBakcPoolPosition.stakedAmount.sub(bakcPrincipal));
    expect(bakcPoolPosition.rewardsDebt).eq(constants.Zero);
  });

  it("withdrawNft: withdraw paired and nonpaired mayc", async () => {
    await advanceHours(100);
    const preRefund = await contracts.nftVault.refundOf(contracts.mayc.address, staker.address);
    expect(preRefund.principal).eq(constants.Zero);
    expect(preRefund.reward).eq(constants.Zero);
    let maycPrincipal = constants.Zero;
    let maycReward = constants.Zero;
    let bakcPrincipal = constants.Zero;
    let bakcReward = constants.Zero;
    let pairedBakcTokenIds = [];

    for (const id of maycTokenIds) {
      const position = await contracts.apeStaking.nftPosition(2, id);
      maycPrincipal = maycPrincipal.add(position.stakedAmount);
      maycReward = maycReward.add(await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id));
      const pairStatus = await contracts.apeStaking.mainToBakc(2, id);
      if (pairStatus.isPaired) {
        const bakcPosition = await contracts.apeStaking.nftPosition(3, pairStatus.tokenId);
        bakcPrincipal = bakcPrincipal.add(bakcPosition.stakedAmount);
        bakcReward = bakcReward.add(
          await contracts.apeStaking.pendingRewards(3, constants.AddressZero, pairStatus.tokenId)
        );
        pairedBakcTokenIds.push(pairStatus.tokenId);
        expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, pairStatus.tokenId)).be.true;
      }
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }

    const bakcStakingNftAmount = await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address);

    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    const preBakcPoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.mayc.address, maycTokenIds)
    ).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.nftVault.address],
      [
        constants.Zero.sub(maycPrincipal).sub(maycReward).sub(bakcPrincipal).sub(bakcReward),
        maycPrincipal.add(maycReward).add(bakcPrincipal).add(bakcReward),
      ]
    );

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

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(
      bakcStakingNftAmount.sub(pairedBakcTokenIds.length)
    );

    for (const id of pairedBakcTokenIds) {
      const position = await contracts.apeStaking.nftPosition(3, id);
      expect(position.stakedAmount).eq(constants.Zero);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(id)).eq(contracts.nftVault.address);
    }
    const bakcRefund = await contracts.nftVault.refundOf(contracts.bakc.address, staker.address);
    expect(bakcRefund.principal).eq(bakcPrincipal);
    expect(bakcRefund.reward).eq(bakcReward);

    const bakcPoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(bakcPoolPosition.stakedAmount).eq(preBakcPoolPosition.stakedAmount.sub(bakcPrincipal));
    expect(bakcPoolPosition.rewardsDebt).eq(constants.Zero);
  });

  it("withdrawNft: withdraw paired bakc", async () => {
    await advanceHours(100);
    const preRefund = await contracts.nftVault.refundOf(contracts.mayc.address, staker.address);
    expect(preRefund.principal).eq(constants.Zero);
    expect(preRefund.reward).eq(constants.Zero);
    let bakcPrincipal = constants.Zero;
    let bakcReward = constants.Zero;

    let pairedBaycTokenIds = [];
    let pairedMaycTokenIds = [];

    for (const id of bakcTokenIds) {
      const position = await contracts.apeStaking.nftPosition(3, id);
      bakcPrincipal = bakcPrincipal.add(position.stakedAmount);
      bakcReward = bakcReward.add(await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id));

      let pairStatus = await contracts.apeStaking.bakcToMain(id, 1);
      if (pairStatus.isPaired) {
        pairedBaycTokenIds.push(pairStatus.tokenId);
      } else {
        pairStatus = await contracts.apeStaking.bakcToMain(id, 2);
        if (pairStatus.isPaired) {
          pairedMaycTokenIds.push(pairStatus.tokenId);
        }
      }
      expect(await contracts.nftVault.isStaking(contracts.bakc.address, staker.address, id)).be.true;
    }

    expect(await contracts.nftVault.totalStakingNft(contracts.bakc.address, staker.address)).eq(bakcTokenIds.length);
    expect(await contracts.nftVault.totalStakingNft(contracts.bayc.address, staker.address)).eq(baycTokenIds.length);
    expect(await contracts.nftVault.totalStakingNft(contracts.mayc.address, staker.address)).eq(maycTokenIds.length);

    const preBakcPoolPosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    await expect(
      contracts.nftVault.connect(owner).withdrawNft(contracts.bakc.address, bakcTokenIds)
    ).changeTokenBalances(
      contracts.apeCoin,
      [contracts.apeStaking.address, contracts.nftVault.address],
      [constants.Zero.sub(bakcPrincipal).sub(bakcReward), bakcPrincipal.add(bakcReward)]
    );

    for (const id of pairedBaycTokenIds) {
      expect(await contracts.bayc.ownerOf(id)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.bayc.address, staker.address, id)).be.true;
    }
    let refund = await contracts.nftVault.refundOf(contracts.bayc.address, staker.address);
    expect(refund.principal).eq(constants.Zero);
    expect(refund.reward).eq(constants.Zero);

    for (const id of pairedMaycTokenIds) {
      expect(await contracts.mayc.ownerOf(id)).eq(contracts.nftVault.address);
      expect(await contracts.nftVault.isStaking(contracts.mayc.address, staker.address, id)).be.true;
    }
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

  it("withdrawNft: withdraw all bayc, and some of paring bakc not in vault", async () => {
    await snapshots.revert("init");
    const baycPaires: ApeCoinStaking.PairNftDepositWithAmountStruct[] = [];
    const maycPaires: ApeCoinStaking.PairNftDepositWithAmountStruct[] = [];
    const officalBakcTokenIds = shuffledSubarray(bakcTokenIds, { minLength: 1, maxLength: 3 });
    for (const [i, id] of officalBakcTokenIds.entries())
      baycPaires.push({
        mainTokenId: baycTokenIds[i],
        bakcTokenId: id,
        amount: makeBN18(856),
      });
    await contracts.apeCoin.connect(owner).approve(contracts.apeStaking.address, constants.MaxUint256);
    await expect(contracts.apeStaking.connect(owner).depositBAKC(baycPaires, maycPaires)).not.reverted;

    await expect(contracts.nftVault.connect(owner).depositNft(contracts.bayc.address, baycTokenIds, staker.address)).not
      .reverted;

    let nfts = [];
    for (let [i, id] of baycTokenIds.entries()) {
      let amount = makeBN18(randomUint(1, 10094));
      nfts[i] = {
        tokenId: id,
        amount,
      };
    }
    await contracts.nftVault.connect(staker).stakeBaycPool(nfts);

    const stakedBakcTokenIds = _.without(bakcTokenIds, ...officalBakcTokenIds);

    let baycNfts: ApeCoinStaking.PairNftDepositWithAmountStruct[] = [];
    let maycNfts: ApeCoinStaking.PairNftDepositWithAmountStruct[] = [];
    let baycIndex = 0;
    for (let id of stakedBakcTokenIds) {
      let amount = makeBN18(randomUint(1, 856));
      baycNfts[baycIndex] = {
        mainTokenId: baycTokenIds[baycIndex + officalBakcTokenIds.length],
        bakcTokenId: id,
        amount,
      };
      baycIndex++;
    }

    await expect(
      contracts.nftVault.connect(owner).depositNft(contracts.bakc.address, stakedBakcTokenIds, staker.address)
    ).not.reverted;

    await expect(contracts.nftVault.connect(staker).stakeBakcPool(baycNfts, maycNfts)).not.reverted;

    await advanceHours(100);

    await expect(contracts.nftVault.connect(owner).withdrawNft(contracts.bayc.address, baycTokenIds)).not.reverted;
  });

  it("withdrawNft: withdraw all mayc, and some of paring bakc not in vault", async () => {
    await snapshots.revert("init");
    const baycPaires: ApeCoinStaking.PairNftDepositWithAmountStruct[] = [];
    const maycPaires: ApeCoinStaking.PairNftDepositWithAmountStruct[] = [];

    const officalBakcTokenIds = shuffledSubarray(bakcTokenIds, { minLength: 1, maxLength: 3 });
    for (const [i, id] of officalBakcTokenIds.entries())
      maycPaires.push({
        mainTokenId: maycTokenIds[i],
        bakcTokenId: id,
        amount: makeBN18(856),
      });
    await contracts.apeCoin.connect(owner).approve(contracts.apeStaking.address, constants.MaxUint256);
    await expect(contracts.apeStaking.connect(owner).depositBAKC(baycPaires, maycPaires)).not.reverted;

    await expect(contracts.nftVault.connect(owner).depositNft(contracts.mayc.address, maycTokenIds, staker.address)).not
      .reverted;

    let nfts = [];
    for (let [i, id] of maycTokenIds.entries()) {
      let amount = makeBN18(randomUint(1, 2042));
      nfts[i] = {
        tokenId: id,
        amount,
      };
    }
    await contracts.nftVault.connect(staker).stakeMaycPool(nfts);

    const stakedBakcTokenIds = _.without(bakcTokenIds, ...officalBakcTokenIds);

    let baycNfts: ApeCoinStaking.PairNftDepositWithAmountStruct[] = [];
    let maycNfts: ApeCoinStaking.PairNftDepositWithAmountStruct[] = [];
    let maycIndex = 0;
    for (let id of stakedBakcTokenIds) {
      let amount = makeBN18(randomUint(1, 856));
      maycNfts[maycIndex] = {
        mainTokenId: maycTokenIds[maycIndex + officalBakcTokenIds.length],
        bakcTokenId: id,
        amount,
      };
      maycIndex++;
    }

    await expect(
      contracts.nftVault.connect(owner).depositNft(contracts.bakc.address, stakedBakcTokenIds, staker.address)
    ).not.reverted;

    await expect(contracts.nftVault.connect(staker).stakeBakcPool(baycNfts, maycNfts)).not.reverted;

    await advanceHours(100);

    await expect(contracts.nftVault.connect(owner).withdrawNft(contracts.mayc.address, maycTokenIds)).not.reverted;
  });
});
