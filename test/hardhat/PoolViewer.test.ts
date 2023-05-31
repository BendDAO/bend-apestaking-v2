import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { makeBNWithDecimals } from "./utils";
import { constants } from "ethers";

makeSuite("PoolViewer", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let lastRevert: string;

  before(async () => {
    owner = env.accounts[1];

    const apeAmountForStakingV1 = makeBNWithDecimals(100000, 18);
    await contracts.apeCoin.connect(env.admin).mint(apeAmountForStakingV1);
    await contracts.apeCoin.connect(env.admin).transfer(contracts.mockStakeManagerV1.address, apeAmountForStakingV1);

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
    await contracts.bendCoinPool.connect(env.feeRecipient).depositSelf(makeBNWithDecimals(1, 18));
    expect(await contracts.bendCoinPool.totalSupply()).gt(0);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("pending rewards", async () => {
    const viewerStatsPool = await contracts.poolViewer.viewPoolPendingRewards();
    expect(viewerStatsPool.baycPoolRewards).eq(0);

    const viewerStatsUser = await contracts.poolViewer.viewUserPendingRewards(env.feeRecipient.address);
    expect(viewerStatsUser.baycPoolRewards).eq(0);
  });
});
