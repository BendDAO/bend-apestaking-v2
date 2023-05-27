import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getContract, makeBN18, mintNft, shuffledSubarray } from "./utils";
import { ethers } from "hardhat";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { BigNumber, constants } from "ethers";
import { IStakedNft, MintableERC721 } from "../../typechain-types";

makeSuite("BendNftPool", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let baycTokenIds: number[];
  let maycTokenIds: number[];
  let bakcTokenIds: number[];
  let lastRevert: string;
  let stakeManagerSigner: SignerWithAddress;

  before(async () => {
    owner = env.accounts[1];
    baycTokenIds = [0, 1, 2, 3, 4, 5];
    await mintNft(owner, contracts.bayc, baycTokenIds);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);
    await contracts.stBayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    maycTokenIds = [6, 7, 8, 9, 10];
    await mintNft(owner, contracts.mayc, maycTokenIds);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);
    await contracts.stMayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    bakcTokenIds = [10, 11, 12, 13, 14];
    await mintNft(owner, contracts.bakc, bakcTokenIds);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);
    await contracts.stBakc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    expect((await contracts.bendNftPool.getPoolStateUI(contracts.bayc.address)).accumulatedRewardsPerNft).eq(0);
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.mayc.address)).accumulatedRewardsPerNft).eq(0);
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.bakc.address)).accumulatedRewardsPerNft).eq(0);

    await impersonateAccount(contracts.bendStakeManager.address);
    stakeManagerSigner = await ethers.getSigner(contracts.bendStakeManager.address);
    await setBalance(stakeManagerSigner.address, makeBN18(1));
    await contracts.apeCoin.connect(stakeManagerSigner).mint(makeBN18(10000));

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("deposit: preparing the first deposit", async () => {
    await contracts.apeCoin.connect(env.feeRecipient).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.bendCoinPool.connect(env.feeRecipient).depositSelf(makeBN18(1));
    expect(await contracts.bendCoinPool.totalSupply()).gt(0);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("receiveApeCoin: no nft", async () => {
    await contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.bayc.address, makeBN18(100));
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.bayc.address)).accumulatedRewardsPerNft).eq(0);

    await contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.mayc.address, makeBN18(100));
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.mayc.address)).accumulatedRewardsPerNft).eq(0);

    await contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.bakc.address, makeBN18(100));
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.bakc.address)).accumulatedRewardsPerNft).eq(0);
  });

  it("deposit: revert when paused", async () => {
    await contracts.bendNftPool.setPause(true);
    await expect(contracts.bendNftPool.connect(owner).deposit([contracts.bayc.address], [baycTokenIds])).revertedWith(
      "Pausable: paused"
    );
    await contracts.bendNftPool.setPause(false);
  });

  it("deposit: revert when duplicate", async () => {
    await expect(
      contracts.bendNftPool.deposit(
        [contracts.bayc.address, contracts.bayc.address, contracts.bakc.address],
        [baycTokenIds, baycTokenIds, bakcTokenIds]
      )
    ).revertedWith("BendNftPool: duplicate nfts");

    await expect(
      contracts.bendNftPool.deposit([contracts.bayc.address], [[baycTokenIds[0], baycTokenIds[0]]])
    ).revertedWith("BendNftPool: duplicate tokenIds");
  });

  it("deposit: deposit bayc", async () => {
    for (const id of baycTokenIds) {
      await expect(contracts.stBayc.ownerOf(id)).revertedWith("ERC721: invalid token ID");
    }
    const index = (await contracts.bendNftPool.getPoolStateUI(contracts.bayc.address)).accumulatedRewardsPerNft;

    await contracts.bendNftPool.connect(owner).deposit([contracts.bayc.address], [baycTokenIds]);
    for (const id of baycTokenIds) {
      expect(await contracts.stBayc.ownerOf(id)).eq(owner.address);
      expect(await contracts.bendNftPool.getNftStateUI(contracts.bayc.address, id)).eq(index);
    }
    lastRevert = "deposit:bayc";
    await snapshots.capture(lastRevert);
  });

  const expectPendingApeCoinChanged = async (block: number, coinAmount: BigNumber, nft: string) => {
    const pending = (await contracts.bendNftPool.getPoolStateUI(nft, { blockTag: block })).pendingApeCoin;
    const prePending = (await contracts.bendNftPool.getPoolStateUI(nft, { blockTag: block - 1 })).pendingApeCoin;
    expect(pending.sub(prePending)).eq(coinAmount);
  };

  const expectIndexChanged = async (block: number, coinAmount: BigNumber, nft: string) => {
    const nftAmount = (await contracts.bendNftPool.getPoolStateUI(nft)).totalStakedNft;
    const shares = await contracts.bendCoinPool.previewDeposit(coinAmount);
    const indexDelta = shares.mul(constants.WeiPerEther).div(nftAmount);
    const index = (await contracts.bendNftPool.getPoolStateUI(nft, { blockTag: block })).accumulatedRewardsPerNft;
    const preIndex = (await contracts.bendNftPool.getPoolStateUI(nft, { blockTag: block - 1 }))
      .accumulatedRewardsPerNft;
    expect(index.sub(preIndex)).eq(indexDelta);
  };

  const expectClaimable = async (nft: string, tokenIds: number[]) => {
    let claimable = constants.Zero;
    const poolState = await contracts.bendNftPool.getPoolStateUI(nft);
    let poolIndex = poolState.accumulatedRewardsPerNft;
    if (poolState.pendingApeCoin.gt(0)) {
      const share = await contracts.bendCoinPool.previewDeposit(poolState.pendingApeCoin);
      poolIndex = poolIndex.add(share.mul(constants.WeiPerEther).div(poolState.totalStakedNft));
    }
    for (const id of tokenIds) {
      let tokenIndex = await contracts.bendNftPool.getNftStateUI(nft, id);
      claimable = claimable.add(poolIndex.sub(tokenIndex).div(constants.WeiPerEther));
    }
    expect(await contracts.bendCoinPool.previewRedeem(claimable)).eq(
      await contracts.bendNftPool.claimable([nft], [tokenIds])
    );
  };

  it("receiveApeCoin: bayc", async () => {
    const coinAmount = makeBN18(100);
    const tx = contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.bayc.address, coinAmount);
    await expectPendingApeCoinChanged((await tx).blockNumber || 0, coinAmount, contracts.bayc.address);
    lastRevert = "receiveApeCoin:bayc";
    await snapshots.capture(lastRevert);
  });

  it("claimable: bayc", async () => {
    const tokenIds = shuffledSubarray(baycTokenIds);
    await expectClaimable(contracts.bayc.address, tokenIds);
  });

  it("deposit: deposit mayc", async () => {
    for (const id of maycTokenIds) {
      await expect(contracts.stMayc.ownerOf(id)).revertedWith("ERC721: invalid token ID");
    }
    const index = (await contracts.bendNftPool.getPoolStateUI(contracts.mayc.address)).accumulatedRewardsPerNft;

    await contracts.bendNftPool.connect(owner).deposit([contracts.mayc.address], [maycTokenIds]);
    for (const id of maycTokenIds) {
      expect(await contracts.stMayc.ownerOf(id)).eq(owner.address);
      expect(await contracts.bendNftPool.getNftStateUI(contracts.mayc.address, id)).eq(index);
    }
    lastRevert = "deposit:mayc";
    await snapshots.capture(lastRevert);
  });

  it("receiveApeCoin: mayc", async () => {
    const coinAmount = makeBN18(100);
    const tx = contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.mayc.address, coinAmount);
    await expectPendingApeCoinChanged((await tx).blockNumber || 0, coinAmount, contracts.mayc.address);
    lastRevert = "receiveApeCoin:mayc";
    await snapshots.capture(lastRevert);
  });

  it("claimable: mayc", async () => {
    const tokenIds = shuffledSubarray(maycTokenIds);
    await expectClaimable(contracts.mayc.address, tokenIds);
  });

  it("deposit: deposit bakc", async () => {
    for (const id of bakcTokenIds) {
      await expect(contracts.stBakc.ownerOf(id)).revertedWith("ERC721: invalid token ID");
    }
    const index = (await contracts.bendNftPool.getPoolStateUI(contracts.bakc.address)).accumulatedRewardsPerNft;

    await contracts.bendNftPool.connect(owner).deposit([contracts.bakc.address], [bakcTokenIds]);
    for (const id of bakcTokenIds) {
      expect(await contracts.stBakc.ownerOf(id)).eq(owner.address);
      expect(await contracts.bendNftPool.getNftStateUI(contracts.bakc.address, id)).eq(index);
    }
    lastRevert = "deposit:bakc";
    await snapshots.capture(lastRevert);
  });

  it("receiveApeCoin: bakc", async () => {
    const coinAmount = makeBN18(100);
    const tx = contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.bakc.address, coinAmount);
    await expectPendingApeCoinChanged((await tx).blockNumber || 0, coinAmount, contracts.bakc.address);
    lastRevert = "receiveApeCoin:bakc";
    await snapshots.capture(lastRevert);
  });

  it("claimable: bakc", async () => {
    const tokenIds = shuffledSubarray(bakcTokenIds);
    await expectClaimable(contracts.bakc.address, tokenIds);
  });

  const expectClaim = async (nft: string, tokenIds: number[]) => {
    const claimable = await contracts.bendNftPool.claimable([nft], [tokenIds]);
    const pendingApeCoin = (await contracts.bendNftPool.getPoolStateUI(nft)).pendingApeCoin;
    const bacApeChanged = await contracts.bendCoinPool.convertToShares(pendingApeCoin.sub(claimable));
    const tx = contracts.bendNftPool.connect(owner).claim([nft], [tokenIds]);
    await expect(tx)
      .changeTokenBalances(
        contracts.apeCoin,
        [owner.address, contracts.bendNftPool.address],
        [claimable, constants.Zero.sub(pendingApeCoin)]
      )
      .changeTokenBalance(contracts.bendCoinPool, contracts.bendNftPool.address, bacApeChanged);
    expectIndexChanged((await tx).blockNumber || 0, pendingApeCoin, nft);
  };

  it("claim", async () => {
    await expectClaim(contracts.bayc.address, shuffledSubarray(baycTokenIds));
    await expectClaim(contracts.mayc.address, shuffledSubarray(maycTokenIds));
    await expectClaim(contracts.bakc.address, shuffledSubarray(bakcTokenIds));
  });

  it("claim: revert when duplicate", async () => {
    await expect(
      contracts.bendNftPool.claimable(
        [contracts.bayc.address, contracts.bayc.address, contracts.bakc.address],
        [baycTokenIds, baycTokenIds, bakcTokenIds]
      )
    ).revertedWith("BendNftPool: duplicate nfts");

    await expect(
      contracts.bendNftPool.claimable([contracts.bayc.address], [[baycTokenIds[0], baycTokenIds[0]]])
    ).revertedWith("BendNftPool: duplicate tokenIds");

    await expect(
      contracts.bendNftPool.claim(
        [contracts.bayc.address, contracts.bayc.address, contracts.bakc.address],
        [baycTokenIds, baycTokenIds, bakcTokenIds]
      )
    ).revertedWith("BendNftPool: duplicate nfts");

    await expect(
      contracts.bendNftPool.claim([contracts.bayc.address], [[baycTokenIds[0], baycTokenIds[0]]])
    ).revertedWith("BendNftPool: duplicate tokenIds");
  });

  it("claim: all", async () => {
    const claimable = await contracts.bendNftPool.claimable(
      [contracts.bayc.address, contracts.mayc.address, contracts.bakc.address],
      [baycTokenIds, maycTokenIds, bakcTokenIds]
    );
    const pendingApeCoin = (await contracts.bendNftPool.getPoolStateUI(contracts.bayc.address)).pendingApeCoin
      .add((await contracts.bendNftPool.getPoolStateUI(contracts.mayc.address)).pendingApeCoin)
      .add((await contracts.bendNftPool.getPoolStateUI(contracts.bakc.address)).pendingApeCoin);

    const bacApeChanged = await contracts.bendCoinPool.convertToShares(pendingApeCoin.sub(claimable));
    const tx = contracts.bendNftPool
      .connect(owner)
      .claim(
        [contracts.bayc.address, contracts.mayc.address, contracts.bakc.address],
        [baycTokenIds, maycTokenIds, bakcTokenIds]
      );
    await expect(tx)
      .changeTokenBalances(
        contracts.apeCoin,
        [owner.address, contracts.bendNftPool.address],
        [claimable, constants.Zero.sub(pendingApeCoin)]
      )
      .changeTokenBalance(contracts.bendCoinPool, contracts.bendNftPool.address, bacApeChanged);
  });

  it("withdraw: revert when paused", async () => {
    await contracts.bendNftPool.setPause(true);
    await expect(contracts.bendNftPool.connect(owner).withdraw([contracts.bayc.address], [baycTokenIds])).revertedWith(
      "Pausable: paused"
    );
    await contracts.bendNftPool.setPause(false);
  });

  it("withdraw: revert when duplicate", async () => {
    await expect(
      contracts.bendNftPool.withdraw(
        [contracts.bayc.address, contracts.bayc.address, contracts.bakc.address],
        [baycTokenIds, baycTokenIds, bakcTokenIds]
      )
    ).revertedWith("BendNftPool: duplicate nfts");

    await expect(
      contracts.bendNftPool.withdraw([contracts.bayc.address], [[baycTokenIds[0], baycTokenIds[0]]])
    ).revertedWith("BendNftPool: duplicate tokenIds");
  });

  const expectWithdraw = async (stNft: IStakedNft, tokenIds: number[]) => {
    const nft = await getContract<MintableERC721>("MintableERC721", await stNft.underlyingAsset());
    const poolState = await contracts.bendNftPool.getPoolStateUI(nft.address);
    const claimable = await contracts.bendNftPool.claimable([nft.address], [tokenIds]);
    const bacApeChanged = await contracts.bendCoinPool.convertToShares(poolState.pendingApeCoin.sub(claimable));

    const tx = contracts.bendNftPool.connect(owner).withdraw([nft.address], [tokenIds]);
    await expect(tx)
      .changeTokenBalances(
        contracts.apeCoin,
        [owner.address, contracts.bendNftPool.address],
        [claimable, constants.Zero.sub(poolState.pendingApeCoin)]
      )
      .changeTokenBalance(contracts.bendCoinPool, contracts.bendNftPool.address, bacApeChanged);
    expectIndexChanged((await tx).blockNumber || 0, poolState.pendingApeCoin, nft.address);

    for (const id of tokenIds) {
      await expect(stNft.ownerOf(id)).revertedWith("ERC721: invalid token ID");
      expect(await nft.ownerOf(id)).eq(owner.address);
    }
  };

  it("withdraw", async () => {
    await expectWithdraw(contracts.stBayc as unknown as IStakedNft, shuffledSubarray(baycTokenIds));
    await expectWithdraw(contracts.stMayc as unknown as IStakedNft, shuffledSubarray(maycTokenIds));
    await expectWithdraw(contracts.stBakc as unknown as IStakedNft, shuffledSubarray(bakcTokenIds));
  });
});
