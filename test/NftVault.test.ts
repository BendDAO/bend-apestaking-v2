import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./_setup";
import { makeBN18, mintNft, randomUint, skipHourBlocks } from "./utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, constants } from "ethers";
import { MintableERC721 } from "../typechain-types";
import { advanceBlock, increaseBy } from "./helpers/block-traveller";

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
    }
    let position = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(position.stakedAmount).eq(constants.Zero);
    expect(position.rewardsDebt).eq(constants.Zero);
    await expect(contracts.nftVault.connect(staker).stakeBaycPool(nfts)).changeTokenBalances(
      contracts.apeCoin,
      [staker.address, contracts.nftVault.address, contracts.apeStaking.address],
      [constants.Zero.sub(stakeAmount), constants.Zero, stakeAmount]
    );

    position = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(position.stakedAmount).eq(stakeAmount);
    expect(position.rewardsDebt).eq(constants.Zero);

    for (let nft of nfts) {
      position = await contracts.apeStaking.nftPosition(1, nft.tokenId);
      expect(position.stakedAmount).eq(nft.amount);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bayc.ownerOf(nft.tokenId)).eq(contracts.nftVault.address);
    }
    lastRevert = "stakeBaycPool";
    await snapshots.capture(lastRevert);
  });

  it("claimBaycPool", async () => {
    await increaseBy(randomUint(3600, 3600 * 100));
    await advanceBlock();
    await skipHourBlocks(60);
    let rewardAmount = constants.Zero;
    let rewardMap = new Map<number, BigNumber>();
    let prePosition = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
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
    for (let id of baycTokenIds) {
      let position = await contracts.apeStaking.nftPosition(1, id);
      expect(position.rewardsDebt).eq(rewardMap.get(id)?.mul(constants.WeiPerEther));
    }
    let position = await contracts.nftVault.positionOf(contracts.bayc.address, staker.address);
    expect(prePosition.stakedAmount).eq(position.stakedAmount);
    expect(position.rewardsDebt).eq(rewardAmount.mul(constants.WeiPerEther));
  });

  it("unstakeBaycPool: unstake fully", async () => {
    await increaseBy(randomUint(3600, 3600 * 100));
    await advanceBlock();
    await skipHourBlocks(60);

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
    }

    await expect(contracts.nftVault.connect(staker).unstakeBaycPool(nfts, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [unstakeAmount.add(rewardAmount), constants.Zero, constants.Zero, constants.Zero]
    );
  });

  it("unstakeBaycPool: unstake partially", async () => {
    await increaseBy(randomUint(3600, 3600 * 100));
    await advanceBlock();
    await skipHourBlocks(60);

    let nfts = [];
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    for (let [i, id] of baycTokenIds.entries()) {
      let amount = (await contracts.apeStaking.nftPosition(1, id)).stakedAmount;
      let reward;
      if (i % 2 === 1) {
        amount = amount.div(2);
        reward = constants.Zero;
      } else {
        reward = await contracts.apeStaking.pendingRewards(1, constants.AddressZero, id);
      }
      nfts[i] = {
        tokenId: id,
        amount,
      };
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
    }

    await expect(contracts.nftVault.connect(staker).unstakeBaycPool(nfts, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [unstakeAmount.add(rewardAmount), constants.Zero, constants.Zero, constants.Zero]
    );
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
    }
    let position = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(position.stakedAmount).eq(constants.Zero);
    expect(position.rewardsDebt).eq(constants.Zero);
    await expect(contracts.nftVault.connect(staker).stakeMaycPool(nfts)).changeTokenBalances(
      contracts.apeCoin,
      [staker.address, contracts.nftVault.address, contracts.apeStaking.address],
      [constants.Zero.sub(stakeAmount), constants.Zero, stakeAmount]
    );

    position = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(position.stakedAmount).eq(stakeAmount);
    expect(position.rewardsDebt).eq(constants.Zero);

    for (let nft of nfts) {
      position = await contracts.apeStaking.nftPosition(2, nft.tokenId);
      expect(position.stakedAmount).eq(nft.amount);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.mayc.ownerOf(nft.tokenId)).eq(contracts.nftVault.address);
    }
    lastRevert = "stakeMaycPool";
    await snapshots.capture(lastRevert);
  });

  it("claimMaycPool", async () => {
    await increaseBy(randomUint(3600, 3600 * 100));
    await advanceBlock();
    await skipHourBlocks(60);
    let rewardAmount = constants.Zero;
    let rewardMap = new Map<number, BigNumber>();
    let prePosition = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    for (let id of maycTokenIds) {
      let amount = await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id);
      rewardMap.set(id, amount);
      rewardAmount = rewardAmount.add(amount);
    }
    await expect(contracts.nftVault.connect(staker).claimMaycPool(maycTokenIds, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [rewardAmount, constants.Zero, constants.Zero, constants.Zero]
    );
    for (let id of maycTokenIds) {
      let position = await contracts.apeStaking.nftPosition(2, id);
      expect(position.rewardsDebt).eq(rewardMap.get(id)?.mul(constants.WeiPerEther));
    }
    let position = await contracts.nftVault.positionOf(contracts.mayc.address, staker.address);
    expect(prePosition.stakedAmount).eq(position.stakedAmount);
    expect(position.rewardsDebt).eq(rewardAmount.mul(constants.WeiPerEther));
  });

  it("unstakeMaycPool: unstake fully", async () => {
    await increaseBy(randomUint(3600, 3600 * 100));
    await advanceBlock();
    await skipHourBlocks(60);

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
    }

    await expect(contracts.nftVault.connect(staker).unstakeMaycPool(nfts, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [unstakeAmount.add(rewardAmount), constants.Zero, constants.Zero, constants.Zero]
    );
  });

  it("unstakeMaycPool: unstake partially", async () => {
    await increaseBy(randomUint(3600, 3600 * 100));
    await advanceBlock();
    await skipHourBlocks(60);

    let nfts = [];
    let unstakeAmount = constants.Zero;
    let rewardAmount = constants.Zero;
    for (let [i, id] of maycTokenIds.entries()) {
      let amount = (await contracts.apeStaking.nftPosition(2, id)).stakedAmount;
      let reward;
      if (i % 2 === 1) {
        amount = amount.div(2);
        reward = constants.Zero;
      } else {
        reward = await contracts.apeStaking.pendingRewards(2, constants.AddressZero, id);
      }
      nfts[i] = {
        tokenId: id,
        amount,
      };
      unstakeAmount = unstakeAmount.add(amount);
      rewardAmount = rewardAmount.add(reward);
    }

    await expect(contracts.nftVault.connect(staker).unstakeMaycPool(nfts, recipient.address)).changeTokenBalances(
      contracts.apeCoin,
      [recipient.address, contracts.nftVault.address, staker.address, owner.address],
      [unstakeAmount.add(rewardAmount), constants.Zero, constants.Zero, constants.Zero]
    );
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
    }
    let position = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(position.stakedAmount).eq(constants.Zero);
    expect(position.rewardsDebt).eq(constants.Zero);
    await expect(contracts.nftVault.connect(staker).stakeBakcPool(baycNfts, maycNfts)).changeTokenBalances(
      contracts.apeCoin,
      [staker.address, contracts.nftVault.address, contracts.apeStaking.address],
      [constants.Zero.sub(stakeAmount), constants.Zero, stakeAmount]
    );

    position = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);
    expect(position.stakedAmount).eq(stakeAmount);
    expect(position.rewardsDebt).eq(constants.Zero);

    for (let nft of baycNfts) {
      position = await contracts.apeStaking.nftPosition(3, nft.bakcTokenId);
      expect(position.stakedAmount).eq(nft.amount);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(nft.bakcTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.bayc.ownerOf(nft.mainTokenId)).eq(contracts.nftVault.address);
    }

    for (let nft of maycNfts) {
      position = await contracts.apeStaking.nftPosition(3, nft.bakcTokenId);
      expect(position.stakedAmount).eq(nft.amount);
      expect(position.rewardsDebt).eq(constants.Zero);
      expect(await contracts.bakc.ownerOf(nft.bakcTokenId)).eq(contracts.nftVault.address);
      expect(await contracts.mayc.ownerOf(nft.mainTokenId)).eq(contracts.nftVault.address);
    }

    lastRevert = "stakeBakcPool";
    await snapshots.capture(lastRevert);
  });

  it("claimBakcPool", async () => {
    await increaseBy(randomUint(3600, 3600 * 100));
    await advanceBlock();
    await skipHourBlocks(60);

    let rewardAmount = constants.Zero;
    let rewardMap = new Map<number, BigNumber>();
    let prePosition = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);

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
      let amount = await contracts.apeStaking.pendingRewards(3, constants.AddressZero, id);
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

    for (let id of bakcTokenIds) {
      let position = await contracts.apeStaking.nftPosition(3, id);
      expect(position.rewardsDebt).eq(rewardMap.get(id)?.mul(constants.WeiPerEther));
    }
    let position = await contracts.nftVault.positionOf(contracts.bakc.address, staker.address);

    expect(prePosition.stakedAmount).eq(position.stakedAmount);
    expect(position.rewardsDebt).eq(rewardAmount.mul(constants.WeiPerEther));
  });
});
