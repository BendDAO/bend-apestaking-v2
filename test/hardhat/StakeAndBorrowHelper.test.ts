import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { advanceHours, makeBNWithDecimals, mintNft } from "./utils";
import { BigNumber, constants } from "ethers";
import { parseEther } from "ethers/lib/utils";

makeSuite("StakeAndBorrowHelper", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let lastRevert: string;
  let baycTokenIds: number[];
  let maycTokenIds: number[];

  before(async () => {
    owner = env.accounts[1];

    const wethAmountForBendPool = parseEther("100");
    await contracts.weth.connect(env.admin).deposit({ value: wethAmountForBendPool });
    await contracts.weth.connect(env.admin).transfer(contracts.mockBendLendPool.address, wethAmountForBendPool);

    const usdtAmountForBendPool = BigNumber.from("100000").mul(1e6);
    await contracts.usdt.connect(env.admin).mint(usdtAmountForBendPool);
    await contracts.usdt.connect(env.admin).transfer(contracts.mockBendLendPool.address, usdtAmountForBendPool);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  afterEach(async () => {
    if (lastRevert) {
      await snapshots.revert(lastRevert);
    }
  });

  it("deposit: preparing some apecoin for stake", async () => {
    await contracts.apeCoin.connect(env.feeRecipient).approve(contracts.bendCoinPool.address, constants.MaxUint256);
    await contracts.bendCoinPool.connect(env.feeRecipient).depositSelf(makeBNWithDecimals(100000, 18));
    expect(await contracts.bendCoinPool.totalAssets()).gt(0);

    await contracts.bendStakeManager.updateBotAdmin(env.admin.address);

    lastRevert = "init";
    await snapshots.capture(lastRevert);
  });

  it("stakeAndBorrow: reverts when paused", async () => {
    await contracts.stakeAndBorrowHelper.setPause(true);

    await expect(
      contracts.stakeAndBorrowHelper
        .connect(owner)
        .stakeAndBorrow([contracts.weth.address], [100000], [contracts.bayc.address], [100])
    ).revertedWith("Pausable: paused");

    await contracts.stakeAndBorrowHelper.setPause(false);
  });

  it("repayAndUnstake: reverts when paused", async () => {
    await contracts.stakeAndBorrowHelper.setPause(true);

    await expect(
      contracts.stakeAndBorrowHelper.connect(owner).repayAndUnstake([contracts.bayc.address], [100])
    ).revertedWith("Pausable: paused");

    await contracts.stakeAndBorrowHelper.setPause(false);
  });

  it("stakeAndBorrow: bayc and weth", async () => {
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.mockBendLendPool.address, true);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.stakeAndBorrowHelper.address, true);

    baycTokenIds = [101, 102, 103];
    await mintNft(owner, contracts.bayc, baycTokenIds);

    const ethBalanceBefore = await owner.getBalance();

    let borrowAmounts = [makeBNWithDecimals(1, 18), makeBNWithDecimals(2, 18), makeBNWithDecimals(3, 18)];

    await contracts.stakeAndBorrowHelper
      .connect(owner)
      .stakeAndBorrow(
        [contracts.weth.address, contracts.weth.address, contracts.weth.address],
        borrowAmounts,
        [contracts.bayc.address, contracts.bayc.address, contracts.bayc.address],
        baycTokenIds
      );

    await contracts.bendStakeManager.connect(env.admin).stakeBayc(baycTokenIds);

    let totalBorrowAmount = BigNumber.from(0);
    for (const [, id] of baycTokenIds.entries()) {
      const nftDebtData = await contracts.mockBendLendPool.getNftDebtData(contracts.stBayc.address, id);
      totalBorrowAmount = totalBorrowAmount.add(nftDebtData.totalDebt);

      expect(await contracts.bayc.ownerOf(id)).eq(contracts.nftVault.address);
      expect(await contracts.stBayc.ownerOf(id)).eq(contracts.mockBendLendPool.address);
      expect(await contracts.mockBendLendPoolLoan.borrowerOf(nftDebtData.loanId)).eq(owner.address);
    }

    let gasUsed = parseEther("0.002");
    expect(await owner.getBalance()).gt(ethBalanceBefore.add(totalBorrowAmount).sub(gasUsed));

    lastRevert = "stakeAndBorrow:bayc:weth";
    await snapshots.capture(lastRevert);
  });

  it("repayAndUnstake: bayc and weth", async () => {
    await advanceHours(12);

    await contracts.bendStakeManager.claimBayc(baycTokenIds);

    const ownerApeCoinBalanceBefore = await contracts.apeCoin.balanceOf(owner.address);

    await contracts.weth.connect(owner).approve(contracts.stakeAndBorrowHelper.address, constants.MaxUint256);
    await contracts.stBayc.connect(owner).setApprovalForAll(contracts.stakeAndBorrowHelper.address, true);

    await contracts.stakeAndBorrowHelper
      .connect(owner)
      .repayAndUnstake([contracts.stBayc.address, contracts.stBayc.address, contracts.stBayc.address], baycTokenIds, {
        value: parseEther("10"),
      });

    for (const [, id] of baycTokenIds.entries()) {
      expect(await contracts.bayc.ownerOf(id)).eq(owner.address);
    }

    expect(await contracts.apeCoin.balanceOf(contracts.stakeAndBorrowHelper.address)).eq(0);

    const ownerApeCoinBalanceAfter = await contracts.apeCoin.balanceOf(owner.address);
    expect(ownerApeCoinBalanceAfter).gt(ownerApeCoinBalanceBefore);

    lastRevert = "init";
  });

  it("stakeAndBorrow: mayc and usdt", async () => {
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.mockBendLendPool.address, true);
    await contracts.mayc.connect(owner).setApprovalForAll(contracts.stakeAndBorrowHelper.address, true);

    maycTokenIds = [201, 202, 203];
    await mintNft(owner, contracts.mayc, maycTokenIds);

    const usdtBalanceBefore = await contracts.usdt.balanceOf(owner.address);

    const usdtDecimals = await contracts.usdt.decimals();
    let borrowAmounts = [
      makeBNWithDecimals(3, usdtDecimals),
      makeBNWithDecimals(2, usdtDecimals),
      makeBNWithDecimals(1, usdtDecimals),
    ];

    await contracts.stakeAndBorrowHelper
      .connect(owner)
      .stakeAndBorrow(
        [contracts.usdt.address, contracts.usdt.address, contracts.usdt.address],
        borrowAmounts,
        [contracts.mayc.address, contracts.mayc.address, contracts.mayc.address],
        maycTokenIds
      );

    await contracts.bendStakeManager.connect(env.admin).stakeMayc(maycTokenIds);

    let totalBorrowAmount = BigNumber.from(0);
    for (const [, id] of maycTokenIds.entries()) {
      const nftDebtData = await contracts.mockBendLendPool.getNftDebtData(contracts.stMayc.address, id);
      totalBorrowAmount = totalBorrowAmount.add(nftDebtData.totalDebt);

      expect(await contracts.mayc.ownerOf(id)).eq(contracts.nftVault.address);
      expect(await contracts.stMayc.ownerOf(id)).eq(contracts.mockBendLendPool.address);
      expect(await contracts.mockBendLendPoolLoan.borrowerOf(nftDebtData.loanId)).eq(owner.address);
    }

    expect(await contracts.usdt.balanceOf(owner.address)).eq(usdtBalanceBefore.add(totalBorrowAmount));

    lastRevert = "stakeAndBorrow:mayc:usdt";
    await snapshots.capture(lastRevert);
  });

  it("repayAndUnstake: mayc and usdt", async () => {
    await advanceHours(10);
    await contracts.bendStakeManager.claimMayc(maycTokenIds);

    const ownerApeCoinBalanceBefore = await contracts.apeCoin.balanceOf(owner.address);

    await contracts.usdt.connect(owner).approve(contracts.stakeAndBorrowHelper.address, constants.MaxUint256);
    await contracts.stMayc.connect(owner).setApprovalForAll(contracts.stakeAndBorrowHelper.address, true);

    const usdtAmountForRepay = BigNumber.from("100").mul(1e6);
    await contracts.usdt.connect(owner).mint(usdtAmountForRepay);

    await contracts.stakeAndBorrowHelper
      .connect(owner)
      .repayAndUnstake([contracts.stMayc.address, contracts.stMayc.address, contracts.stMayc.address], maycTokenIds);

    for (const [, id] of maycTokenIds.entries()) {
      expect(await contracts.mayc.ownerOf(id)).eq(owner.address);
    }

    expect(await contracts.apeCoin.balanceOf(contracts.stakeAndBorrowHelper.address)).eq(0);

    const ownerApeCoinBalanceAfter = await contracts.apeCoin.balanceOf(owner.address);
    expect(ownerApeCoinBalanceAfter).gt(ownerApeCoinBalanceBefore);

    lastRevert = "init";
  });
});
