import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { constants } from "ethers";
import { DefaultRewardsStrategy } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

makeSuite("DefaultRewardsStrategy", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let hacker: SignerWithAddress;
  let lastRevert: string;
  let baycStrategy: DefaultRewardsStrategy;

  before(async () => {
    hacker = env.accounts[2];

    lastRevert = "init";

    baycStrategy = contracts.baycStrategy as DefaultRewardsStrategy;

    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("onlyOwner: reverts", async () => {
    await expect(baycStrategy.connect(hacker).setNftRewardsShare(constants.AddressZero)).revertedWith(
      "Ownable: caller is not the owner"
    );
  });

  it("setNftRewardsShare", async () => {
    const newNftShare = 5432;

    await baycStrategy.setNftRewardsShare(newNftShare);

    expect(await contracts.baycStrategy.getNftRewardsShare()).eq(newNftShare);
  });
});
