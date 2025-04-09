import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "../setup";
import { mintNft } from "../utils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MintableERC721, IStakedNft } from "../../../typechain-types";
import { constants } from "ethers";
import { arrayify } from "ethers/lib/utils";

export function makeStNftTest(name: string, getNfts: (contracts: Contracts) => [IStakedNft, MintableERC721]): void {
  makeSuite(name, (contracts: Contracts, env: Env, snapshots: Snapshots) => {
    let staker: SignerWithAddress;
    let stNftOwner: SignerWithAddress;
    let lastRevert: string;
    let tokenIds: number[];
    let nft: MintableERC721;
    let stNft: IStakedNft;

    before(async () => {
      staker = env.accounts[1];
      stNftOwner = env.accounts[2];
      [stNft, nft] = getNfts(contracts);
      expect(await stNft.underlyingAsset()).eq(nft.address);

      tokenIds = [0, 1, 2, 3, 4, 5];
      await mintNft(staker, nft, tokenIds);
      for (const id of tokenIds) {
        expect(await stNft.tokenURI(id)).eq(await nft.tokenURI(id));
      }
      await nft.connect(staker).setApprovalForAll(stNft.address, true);

      lastRevert = "init";
      await snapshots.capture(lastRevert);
    });

    afterEach(async () => {
      if (lastRevert) {
        await snapshots.revert(lastRevert);
      }
    });

    it("onlyAuthorized: reverts", async () => {
      await expect(stNft.connect(staker).mint(stNftOwner.address, tokenIds)).revertedWith(
        "StNft: caller is not authorized"
      );

      await stNft.connect(env.admin).authorise(staker.address, true);
      lastRevert = "init";
      await snapshots.capture(lastRevert);
    });

    it("mint", async () => {
      expect(await stNft.totalStaked(staker.address)).eq(0);
      expect(await stNft.totalStaked(stNftOwner.address)).eq(0);
      await expect(stNft.connect(staker).mint(stNftOwner.address, tokenIds)).not.reverted;

      expect(await stNft.totalStaked(staker.address)).eq(tokenIds.length);
      expect(await stNft.totalStaked(stNftOwner.address)).eq(0);
      for (const [i, id] of tokenIds.entries()) {
        expect(await contracts.nftVault.stakerOf(nft.address, id)).eq(staker.address);
        expect(await nft.ownerOf(id)).eq(contracts.nftVault.address);
        expect(await stNft.ownerOf(id)).eq(stNftOwner.address);
        expect(await stNft.tokenOfStakerByIndex(staker.address, i)).eq(id);
      }
      lastRevert = "mint";
      await snapshots.capture(lastRevert);
    });

    it("setDelegateCash", async () => {
      {
        await stNft.connect(stNftOwner).setDelegateCash(stNftOwner.address, tokenIds, true);

        const delegates = await stNft.getDelegateCashForToken(tokenIds);
        expect(delegates.length).eq(tokenIds.length);
        for (let i = 0; i < delegates.length; i++) {
          expect(delegates[i].length).eq(1);
          expect(delegates[i][0]).eq(stNftOwner.address);
        }
      }

      {
        await stNft.connect(stNftOwner).setDelegateCash(stNftOwner.address, tokenIds, false);

        const delegates = await stNft.getDelegateCashForToken(tokenIds);
        expect(delegates.length).eq(tokenIds.length);
        for (let i = 0; i < delegates.length; i++) {
          expect(delegates[i].length).eq(0);
        }
      }

      lastRevert = "mint";
    });

    it("setDelegateCashV2", async () => {
      {
        await stNft.connect(stNftOwner).setDelegateCashV2(stNftOwner.address, tokenIds, true);

        const { delegates } = await stNft.getDelegateCashForTokenV2(tokenIds);
        expect(delegates.length).eq(tokenIds.length);
        for (let i = 0; i < delegates.length; i++) {
          expect(delegates[i].length).eq(1);
          expect(delegates[i][0]).eq(stNftOwner.address);
        }
      }

      {
        await stNft.connect(stNftOwner).setDelegateCashV2(stNftOwner.address, tokenIds, false);

        const { delegates } = await stNft.getDelegateCashForTokenV2(tokenIds);
        expect(delegates.length).eq(tokenIds.length);
        for (let i = 0; i < delegates.length; i++) {
          expect(delegates[i].length).eq(0);
        }
      }

      lastRevert = "mint";
    });

    it("setDelegateCashV2WithRights", async () => {
      const rights = arrayify("0x000000000000000000000000000000000000000000000000000000ffffffffff");

      {
        await stNft.connect(stNftOwner).setDelegateCashV2WithRights(stNftOwner.address, tokenIds, rights, true);

        const { delegates } = await stNft.getDelegateCashForTokenV2(tokenIds);
        expect(delegates.length).eq(tokenIds.length);
        for (let i = 0; i < delegates.length; i++) {
          expect(delegates[i].length).eq(1);
          expect(delegates[i][0]).eq(stNftOwner.address);
        }
      }

      {
        await stNft.connect(stNftOwner).setDelegateCashV2WithRights(stNftOwner.address, tokenIds, rights, false);

        const { delegates } = await stNft.getDelegateCashForTokenV2(tokenIds);
        expect(delegates.length).eq(tokenIds.length);
        for (let i = 0; i < delegates.length; i++) {
          expect(delegates[i].length).eq(0);
        }
      }

      lastRevert = "mint";
    });

    it("burn", async () => {
      expect(await stNft.totalStaked(staker.address)).eq(tokenIds.length);
      expect(await stNft.totalStaked(stNftOwner.address)).eq(0);

      await expect(stNft.connect(stNftOwner).burn(tokenIds)).not.reverted;

      expect(await stNft.totalStaked(staker.address)).eq(0);
      expect(await stNft.totalStaked(stNftOwner.address)).eq(0);

      for (const [i, id] of tokenIds.entries()) {
        expect(await contracts.nftVault.stakerOf(nft.address, id)).eq(constants.AddressZero);
        expect(await nft.ownerOf(id)).eq(stNftOwner.address);
        await expect(stNft.ownerOf(id)).revertedWith("ERC721: invalid token ID");
        await expect(stNft.tokenOfStakerByIndex(staker.address, i)).revertedWith("stNft: staker index out of bounds");
      }
    });
  });
}
