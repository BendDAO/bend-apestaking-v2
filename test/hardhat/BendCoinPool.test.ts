import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { BigNumber, constants, Contract } from "ethers";
import { deployContract, makeBN18 } from "./utils";
import { impersonateAccount, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { BendCoinPool, MockBendStakeManager } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

makeSuite("BendCoinPool", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let lastRevert: string;
  let staker: MockBendStakeManager;
  let pool: BendCoinPool;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  before(async () => {
    pool = await deployContract<BendCoinPool>("BendCoinPool", []);
    staker = await deployContract<MockBendStakeManager>("MockBendStakeManager", [
      contracts.apeCoin.address,
      pool.address,
      makeBN18(1000),
    ]);
    await impersonateAccount(staker.address);
    await setBalance(staker.address, makeBN18(1));

    alice = env.accounts[1];
    bob = env.accounts[2];

    await contracts.apeCoin.connect(alice).approve(pool.address, constants.MaxUint256);
    await contracts.apeCoin.connect(bob).approve(pool.address, constants.MaxUint256);

    await (pool as Contract).initialize(contracts.apeStaking.address, staker.address);
    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });
  const expectPendingAmountChanged = async (blockTag: number, delta: BigNumber) => {
    expect(
      (await pool.pendingApeCoin({ blockTag })).sub(await pool.pendingApeCoin({ blockTag: blockTag - 1 })).eq(delta)
    );
  };

  it("deposit: revert when paused", async () => {
    let depositAmount = makeBN18(10000);

    await pool.setPause(true);
    await expect(pool.connect(bob).depositSelf(depositAmount)).revertedWith("Pausable: paused");
    await pool.setPause(false);
  });

  it("deposit", async () => {
    let depositAmount = makeBN18(10000);
    let tx = pool.connect(alice).depositSelf(depositAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [alice.address, pool.address],
      [constants.Zero.sub(depositAmount), depositAmount]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, depositAmount);

    depositAmount = makeBN18(100);
    tx = pool.connect(bob).depositSelf(depositAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [bob.address, pool.address],
      [constants.Zero.sub(depositAmount), depositAmount]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, depositAmount);

    lastRevert = "deposit";
    await snapshots.capture(lastRevert);
  });

  it("withdraw: revert when paused", async () => {
    const withdrawAmount = await pool.assetBalanceOf(bob.address);

    await pool.setPause(true);
    await expect(pool.connect(bob).withdrawSelf(withdrawAmount)).revertedWith("Pausable: paused");
    await pool.setPause(false);
  });

  it("withdraw: from pending ape coin", async () => {
    const withdrawAmount = await pool.assetBalanceOf(bob.address);
    const tx = pool.connect(bob).withdrawSelf(withdrawAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [bob.address, pool.address],
      [withdrawAmount, constants.Zero.sub(withdrawAmount)]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, constants.Zero.sub(withdrawAmount));
  });

  it("pullApeCoin", async () => {
    const pullAmount = makeBN18(10050);
    const stakerSigner = await ethers.getSigner(staker.address);
    await expect(pool.pullApeCoin(pullAmount)).revertedWith("BendCoinPool: caller is not staker");
    const tx = pool.connect(stakerSigner).pullApeCoin(pullAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [pool.address, staker.address],
      [constants.Zero.sub(pullAmount), pullAmount]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, constants.Zero.sub(pullAmount));
    lastRevert = "pullApeCoin";
    await snapshots.capture(lastRevert);
  });

  it("withdraw: from stake manager", async () => {
    const withdrawAmount = await pool.assetBalanceOf(bob.address);
    const pendingApeCoin = await pool.pendingApeCoin();

    const tx = pool.connect(bob).withdrawSelf(withdrawAmount);
    await expect(tx).changeTokenBalances(
      contracts.apeCoin,
      [bob.address, pool.address, staker.address],
      [withdrawAmount, constants.Zero.sub(pendingApeCoin), constants.Zero.sub(withdrawAmount).add(pendingApeCoin)]
    );
    await expectPendingAmountChanged((await tx).blockNumber || 0, constants.Zero.sub(pendingApeCoin));
  });

  it("withdraw: withdraw failed", async () => {
    await pool.connect(bob).withdrawSelf(await pool.assetBalanceOf(bob.address));
    const withdrawAmount = await pool.assetBalanceOf(alice.address);
    await expect(pool.connect(alice).withdrawSelf(withdrawAmount)).revertedWith("BendCoinPool: withdraw failed");
  });
});
