import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "../_setup";
import { mintNft } from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MintableERC721, IStakedNft } from "../../../typechain-types";
import { constants } from "ethers";

export function makeStNftTest(name: string, getNfts: (contracts: Contracts) => [IStakedNft, MintableERC721]): void {
  makeSuite(name, (contracts: Contracts, env: Env, snapshots: Snapshots) => {
    let staker: SignerWithAddress;
    let owner: SignerWithAddress;
    let receiver: SignerWithAddress;
    let lastRevert: string;
    let tokenIds: number[];
    let nft: MintableERC721;
    let stNft: IStakedNft;

    before(async () => {
      staker = env.admin;
      owner = env.accounts[1];
      receiver = env.accounts[2];
      [stNft, nft] = getNfts(contracts);
      expect(await stNft.underlyingAsset()).eq(nft.address);

      tokenIds = [0, 1, 2, 3, 4, 5];
      await mintNft(owner, nft, tokenIds);
      for (const id of tokenIds) {
        expect(await stNft.tokenURI(id)).eq(await nft.tokenURI(id));
      }
      await nft.connect(owner).setApprovalForAll(stNft.address, true);

      lastRevert = "init";
      await snapshots.capture(lastRevert);
    });

    afterEach(async () => {
      if (lastRevert) {
        await snapshots.revert(lastRevert);
      }
    });

    it("mint", async () => {
      expect(await stNft.totalStaked(staker.address)).eq(0);
      expect(await stNft.totalStaked(owner.address)).eq(0);
      expect(await stNft.totalStaked(receiver.address)).eq(0);
      await expect(stNft.connect(owner).mint(staker.address, receiver.address, tokenIds)).not.reverted;

      expect(await stNft.totalStaked(staker.address)).eq(tokenIds.length);
      expect(await stNft.totalStaked(owner.address)).eq(0);
      expect(await stNft.totalStaked(receiver.address)).eq(0);
      for (const [i, id] of tokenIds.entries()) {
        expect(await contracts.nftVault.stakerOf(nft.address, id)).eq(staker.address);
        expect(await nft.ownerOf(id)).eq(contracts.nftVault.address);
        expect(await stNft.ownerOf(id)).eq(receiver.address);
        expect(await stNft.minterOf(id)).eq(owner.address);
        expect(await stNft.tokenOfStakerByIndex(staker.address, i)).eq(id);
      }
      lastRevert = "mint";
      await snapshots.capture(lastRevert);
    });

    it("burn", async () => {
      expect(await stNft.totalStaked(staker.address)).eq(tokenIds.length);
      expect(await stNft.totalStaked(owner.address)).eq(0);
      expect(await stNft.totalStaked(receiver.address)).eq(0);

      await expect(stNft.connect(receiver).burn(tokenIds)).not.reverted;

      expect(await stNft.totalStaked(staker.address)).eq(0);
      expect(await stNft.totalStaked(owner.address)).eq(0);
      expect(await stNft.totalStaked(receiver.address)).eq(0);

      for (const [i, id] of tokenIds.entries()) {
        expect(await contracts.nftVault.stakerOf(nft.address, id)).eq(constants.AddressZero);
        expect(await nft.ownerOf(id)).eq(receiver.address);
        await expect(stNft.ownerOf(id)).revertedWith("ERC721: invalid token ID");
        expect(await stNft.minterOf(id)).eq(constants.AddressZero);
        await expect(stNft.tokenOfStakerByIndex(staker.address, i)).revertedWith("stNft: staker index out of bounds");
      }
    });
  });
}
