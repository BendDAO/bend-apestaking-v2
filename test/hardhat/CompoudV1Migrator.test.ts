import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { makeBNWithDecimals } from "./utils";
import { constants } from "ethers";

makeSuite("CompoudV1Migrator", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let lastRevert: string;

  before(async () => {
    owner = env.accounts[1];

    const apeAmountForStakingV1 = makeBNWithDecimals(100000, 18);
    await contracts.wrapApeCoin.connect(env.admin).deposit({ value: apeAmountForStakingV1 });
    await contracts.wrapApeCoin
      .connect(env.admin)
      .transfer(contracts.mockStakeManagerV1.address, apeAmountForStakingV1);

    lastRevert = "init";

    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("deposit: preparing the first deposit", async () => {
    await contracts.wrapApeCoin.connect(env.feeRecipient).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.bendCoinPool.connect(env.feeRecipient).depositSelf(makeBNWithDecimals(1, 18));
    expect(await contracts.bendCoinPool.totalSupply()).gt(0);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("claim v1 and deposit", async () => {
    await contracts.wrapApeCoin.connect(owner).approve(contracts.compoudV1Migrator.address, constants.MaxUint256);
    const rewardsAmount = await contracts.mockStakeManagerV1.REWARDS_AMOUNT();

    await contracts.compoudV1Migrator.connect(owner).claimV1AndDeposit([owner.address]);

    expect(await contracts.bendCoinPool.assetBalanceOf(owner.address)).eq(rewardsAmount);
  });

  it("withdraw v1 and deposit", async () => {
    await contracts.wrapApeCoin.connect(owner).approve(contracts.mockCoinPoolV1.address, constants.MaxUint256);
    const apeAmountForStakingV1 = makeBNWithDecimals(123, 18);
    await contracts.mockCoinPoolV1.connect(owner).deposit(apeAmountForStakingV1, owner.address);
    expect(await contracts.mockCoinPoolV1.assetBalanceOf(owner.address)).eq(apeAmountForStakingV1);

    await contracts.mockCoinPoolV1.connect(owner).approve(contracts.compoudV1Migrator.address, constants.MaxUint256);
    await contracts.compoudV1Migrator.connect(owner).withdrawV1AndDeposit();

    expect(await contracts.mockCoinPoolV1.assetBalanceOf(owner.address)).eq(constants.Zero);
    expect(await contracts.bendCoinPool.assetBalanceOf(owner.address)).eq(apeAmountForStakingV1);
  });
});
