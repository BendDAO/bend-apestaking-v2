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

    maycTokenIds = [6, 7, 8, 9, 10];
    await mintNft(owner, contracts.mayc, maycTokenIds);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);

    bakcTokenIds = [10, 11, 12, 13, 14];
    await mintNft(owner, contracts.bakc, bakcTokenIds);
    await contracts.bakc.connect(owner).setApprovalForAll(contracts.bendNftPool.address, true);
    lastRevert = "init";

    expect((await contracts.bendNftPool.getPoolStateUI(contracts.bayc.address)).accumulatedRewardsPerNft).eq(0);
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.mayc.address)).accumulatedRewardsPerNft).eq(0);
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.bakc.address)).accumulatedRewardsPerNft).eq(0);

    await impersonateAccount(contracts.bendStakeManager.address);
    stakeManagerSigner = await ethers.getSigner(contracts.bendStakeManager.address);
    await setBalance(stakeManagerSigner.address, makeBN18(1));
    await contracts.apeCoin.connect(stakeManagerSigner).mint(makeBN18(10000));

    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("receiveApeCoin: no nft", async () => {
    await contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.bayc.address, makeBN18(100));
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.bayc.address)).accumulatedRewardsPerNft).eq(0);

    await contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.mayc.address, makeBN18(100));
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.mayc.address)).accumulatedRewardsPerNft).eq(0);

    await contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.bakc.address, makeBN18(100));
    expect((await contracts.bendNftPool.getPoolStateUI(contracts.bakc.address)).accumulatedRewardsPerNft).eq(0);
  });

  it("deposit: deposit bayc", async () => {
    for (const id of baycTokenIds) {
      await expect(contracts.stBayc.ownerOf(id)).revertedWith("ERC721: invalid token ID");
    }
    const index = (await contracts.bendNftPool.getPoolStateUI(contracts.bayc.address)).accumulatedRewardsPerNft;

    await contracts.bendNftPool.connect(owner).deposit(contracts.bayc.address, baycTokenIds);
    for (const id of baycTokenIds) {
      expect(await contracts.stBayc.ownerOf(id)).eq(owner.address);
      expect(await contracts.bendNftPool.getNftStateUI(contracts.bayc.address, id)).eq(index);
    }
    lastRevert = "deposit:bayc";
    await snapshots.capture(lastRevert);
  });

  const expectIndexChanged = async (block: number, coinAmount: BigNumber, nft: string) => {
    const nftAmount = (await contracts.bendNftPool.getPoolStateUI(nft)).totalNfts;
    const shares = await contracts.bendCoinPool.previewDeposit(coinAmount);
    const indexDelta = shares.mul(constants.WeiPerEther).div(nftAmount);
    expect(
      (await contracts.bendNftPool.getPoolStateUI(nft, { blockTag: block })).accumulatedRewardsPerNft
        .sub((await contracts.bendNftPool.getPoolStateUI(nft, { blockTag: block - 1 })).accumulatedRewardsPerNft)
        .eq(indexDelta)
    );
  };

  const expectClaimable = async (nft: string, tokenIds: number[]) => {
    let claimable = constants.Zero;
    const poolIndex = (await contracts.bendNftPool.getPoolStateUI(nft)).accumulatedRewardsPerNft;
    let index;
    for (const id of tokenIds) {
      index = await contracts.bendNftPool.getNftStateUI(nft, id);
      claimable = claimable.add(poolIndex.sub(index).div(constants.WeiPerEther));
    }
    expect(await contracts.bendCoinPool.previewRedeem(claimable)).eq(
      await contracts.bendNftPool.claimable(nft, tokenIds)
    );
  };

  it("receiveApeCoin: bayc", async () => {
    const coinAmount = makeBN18(100);
    const tx = contracts.bendNftPool.connect(stakeManagerSigner).receiveApeCoin(contracts.bayc.address, coinAmount);
    await expectIndexChanged((await tx).blockNumber || 0, coinAmount, contracts.bayc.address);
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

    await contracts.bendNftPool.connect(owner).deposit(contracts.mayc.address, maycTokenIds);
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
    await expectIndexChanged((await tx).blockNumber || 0, coinAmount, contracts.mayc.address);
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

    await contracts.bendNftPool.connect(owner).deposit(contracts.bakc.address, bakcTokenIds);
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
    await expectIndexChanged((await tx).blockNumber || 0, coinAmount, contracts.bakc.address);
  });

  it("claimable: bakc", async () => {
    const tokenIds = shuffledSubarray(bakcTokenIds);
    await expectClaimable(contracts.bakc.address, tokenIds);
  });

  const expectClaim = async (nft: string, tokenIds: number[]) => {
    const claimable = await contracts.bendNftPool.claimable(nft, tokenIds);
    await expect(contracts.bendNftPool.connect(owner).claim(nft, tokenIds))
      .changeTokenBalances(
        contracts.apeCoin,
        [owner.address, contracts.bendNftPool.address],
        [claimable, constants.Zero]
      )
      .changeTokenBalance(
        contracts.bendCoinPool,
        contracts.bendNftPool.address,
        constants.Zero.sub(await contracts.bendCoinPool.convertToShares(claimable))
      );
  };

  it("claim", async () => {
    await expectClaim(contracts.bayc.address, shuffledSubarray(baycTokenIds));
    await expectClaim(contracts.mayc.address, shuffledSubarray(maycTokenIds));
    await expectClaim(contracts.bakc.address, shuffledSubarray(bakcTokenIds));
  });

  const expectWithdraw = async (stNft: IStakedNft, tokenIds: number[]) => {
    const nft = await getContract<MintableERC721>("MintableERC721", await stNft.underlyingAsset());
    const claimable = await contracts.bendNftPool.claimable(nft.address, tokenIds);
    await expect(contracts.bendNftPool.connect(owner).withdraw(nft.address, tokenIds))
      .changeTokenBalances(
        contracts.apeCoin,
        [owner.address, contracts.bendNftPool.address],
        [claimable, constants.Zero]
      )
      .changeTokenBalance(
        contracts.bendCoinPool,
        contracts.bendNftPool.address,
        constants.Zero.sub(await contracts.bendCoinPool.convertToShares(claimable))
      );
    for (const id of tokenIds) {
      await expect(stNft.ownerOf(id)).revertedWith("ERC721: invalid token ID");
      expect(await nft.ownerOf(id)).eq(owner.address);
    }
  };

  it("withdraw", async () => {
    expectWithdraw(contracts.stBayc as unknown as IStakedNft, shuffledSubarray(baycTokenIds));
    expectWithdraw(contracts.stMayc as unknown as IStakedNft, shuffledSubarray(maycTokenIds));
    expectWithdraw(contracts.stBakc as unknown as IStakedNft, shuffledSubarray(bakcTokenIds));
  });
});
