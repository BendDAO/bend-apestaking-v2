import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { BigNumber, constants } from "ethers";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { makeBN18 } from "./utils";

makeSuite("BendCoinPool", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let bot: SignerWithAddress;
  let lastRevert: string;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  before(async () => {
    await impersonateAccount(contracts.bendStakeManager.address);
    await setBalance(contracts.bendStakeManager.address, makeBN18(1));
    bot = env.admin;
    alice = env.accounts[1];
    bob = env.accounts[2];

    await contracts.apeCoin.connect(alice).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.apeCoin.connect(bob).approve(contracts.bendCoinPool.address, constants.MaxUint256);

    await contracts.bendStakeManager.updateBotAdmin(bot.address);
    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });
  const expectPendingAmountChanged = async (blockTag: number, delta: BigNumber) => {
    const now = await contracts.bendCoinPool.pendingApeCoin({ blockTag });
    const pre = await contracts.bendCoinPool.pendingApeCoin({ blockTag: blockTag - 1 });
    expect(now.sub(pre)).eq(delta);
  };

  it("deposit: preparing the first deposit", async () => {
    await contracts.apeCoin.connect(env.feeRecipient).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.bendCoinPool.connect(env.feeRecipient).depositSelf(makeBN18(1));
    expect(await contracts.bendCoinPool.totalSupply()).gt(0);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("deposit: revert when paused", async () => {
    let depositAmount = makeBN18(10000);

    await contracts.bendCoinPool.setPause(true);
    await expect(contracts.bendCoinPool.connect(bob).depositSelf(depositAmount)).revertedWith("Pausable: paused");
    await contracts.bendCoinPool.setPause(false);
  });

  it("deposit", async () => {
    let depositAmount = makeBN18(10000);
    let tx = contracts.bendCoinPool.connect(alice).depositSelf(depositAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [alice.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(depositAmount), depositAmount]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, depositAmount);

    depositAmount = makeBN18(100);
    tx = contracts.bendCoinPool.connect(bob).mintSelf(await contracts.bendCoinPool.previewMint(depositAmount));
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [bob.address, contracts.bendCoinPool.address],
      [constants.Zero.sub(depositAmount), depositAmount]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, depositAmount);

    lastRevert = "deposit";
    await snapshots.capture(lastRevert);
  });

  it("getVotes", async () => {
    const assetsAmount = await contracts.bendCoinPool.assetBalanceOf(bob.address);
    const votesAmount = await contracts.stakedVoting.getVotes(bob.address);
    expect(assetsAmount).eq(votesAmount);
  });

  it("withdraw: revert when paused", async () => {
    const withdrawAmount = await contracts.bendCoinPool.assetBalanceOf(bob.address);
    await contracts.bendCoinPool.setPause(true);
    await expect(contracts.bendCoinPool.connect(bob).withdrawSelf(withdrawAmount)).revertedWith("Pausable: paused");
    await contracts.bendCoinPool.setPause(false);
  });

  it("redeem: revert when paused", async () => {
    const withdrawAmount = await contracts.bendCoinPool.assetBalanceOf(bob.address);
    await contracts.bendCoinPool.setPause(true);
    await expect(contracts.bendCoinPool.connect(bob).redeemSelf(withdrawAmount)).revertedWith("Pausable: paused");
    await contracts.bendCoinPool.setPause(false);
  });

  it("withdraw: from pending ape coin", async () => {
    const withdrawAmount = await contracts.bendCoinPool.assetBalanceOf(bob.address);
    const tx = contracts.bendCoinPool.connect(bob).withdrawSelf(withdrawAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [bob.address, contracts.bendCoinPool.address],
      [withdrawAmount, constants.Zero.sub(withdrawAmount)]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, constants.Zero.sub(withdrawAmount));
  });

  it("redeem: from pending ape coin", async () => {
    const withdrawAmount = await contracts.bendCoinPool.balanceOf(bob.address);
    const apeCoinAmount = await contracts.bendCoinPool.previewRedeem(withdrawAmount);
    const tx = contracts.bendCoinPool.connect(bob).redeemSelf(withdrawAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [bob.address, contracts.bendCoinPool.address],
      [apeCoinAmount, constants.Zero.sub(apeCoinAmount)]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, constants.Zero.sub(apeCoinAmount));
  });

  it("pullApeCoin", async () => {
    const pullAmount = (await contracts.bendCoinPool.pendingApeCoin()).sub(makeBN18(1));
    const tx = contracts.bendStakeManager.stakeApeCoin(pullAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [contracts.bendCoinPool.address, contracts.bendStakeManager.address, contracts.apeStaking.address],
      [constants.Zero.sub(pullAmount), constants.Zero, pullAmount]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, constants.Zero.sub(pullAmount));

    lastRevert = "pullApeCoin";
    await snapshots.capture(lastRevert);
  });

  it("withdraw: from withdraw strategy", async () => {
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    const withdrawAmount = await contracts.bendCoinPool.assetBalanceOf(bob.address);
    const tx = contracts.bendCoinPool.connect(bob).withdrawSelf(withdrawAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [bob.address, contracts.apeStaking.address],
      [withdrawAmount, pendingApeCoin.sub(withdrawAmount)]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, constants.Zero.sub(pendingApeCoin));
  });

  it("redeem: from withdraw strategy", async () => {
    const pendingApeCoin = await contracts.bendCoinPool.pendingApeCoin();
    const withdrawAmount = await contracts.bendCoinPool.balanceOf(bob.address);
    const apeCoinAmount = await contracts.bendCoinPool.previewRedeem(withdrawAmount);
    const tx = contracts.bendCoinPool.connect(bob).redeemSelf(withdrawAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [bob.address, contracts.apeStaking.address],
      [apeCoinAmount, pendingApeCoin.sub(withdrawAmount)]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, constants.Zero.sub(pendingApeCoin));
  });
});
