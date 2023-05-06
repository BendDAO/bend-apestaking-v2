import { expect } from "chai";
import { Contracts, Env, makeSuite, Snapshots } from "./setup";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { makeBNWithDecimals, mintNft } from "./utils";
import { BigNumber, constants } from "ethers";
import { defaultAbiCoder, parseEther } from "ethers/lib/utils";

makeSuite("LendingMigrator", (contracts: Contracts, env: Env, snapshots: Snapshots) => {
  let owner: SignerWithAddress;
  let lastRevert: string;
  let baycTokenIds: number[];

  before(async () => {
    owner = env.accounts[1];

    const wethAmountForAavePool = parseEther("100");
    await contracts.weth.connect(env.admin).mint(wethAmountForAavePool);
    await contracts.weth.connect(env.admin).transfer(contracts.mockAaveLendPool.address, wethAmountForAavePool);

    const usdtAmountForAavePool = BigNumber.from("100000").mul(1e6);
    await contracts.usdt.connect(env.admin).mint(usdtAmountForAavePool);
    await contracts.usdt.connect(env.admin).transfer(contracts.mockAaveLendPool.address, usdtAmountForAavePool);

    const wethAmountForBendPool = parseEther("100");
    await contracts.weth.connect(env.admin).mint(wethAmountForBendPool);
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

  it("testMultipleNftWithoutAuction", async () => {
    await contracts.weth.connect(owner).approve(contracts.mockBendLendPool.address, constants.MaxUint256);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.mockBendLendPool.address, true);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.lendingMigrator.address, true);

    baycTokenIds = [101, 102, 103];
    await mintNft(owner, contracts.bayc, baycTokenIds);

    let borrowAmounts = [makeBNWithDecimals(1, 18), makeBNWithDecimals(2, 18), makeBNWithDecimals(3, 18)];
    let totalBorrowAmounts = BigNumber.from(0);

    for (const [i, id] of baycTokenIds.entries()) {
      totalBorrowAmounts = totalBorrowAmounts.add(borrowAmounts[i]);
      await contracts.mockBendLendPool
        .connect(owner)
        .borrow(contracts.weth.address, borrowAmounts[i], contracts.bayc.address, id, owner.address, 0);
    }

    const params = defaultAbiCoder.encode(
      ["address[]", "uint256[]"],
      [[contracts.bayc.address, contracts.bayc.address, contracts.bayc.address], baycTokenIds]
    );

    await contracts.mockAaveLendPool.flashLoan(
      contracts.lendingMigrator.address,
      [contracts.weth.address],
      [totalBorrowAmounts],
      [0],
      owner.address,
      params,
      0
    );

    for (const [, id] of baycTokenIds.entries()) {
      const nftLoanId = await contracts.mockBendLendPoolLoan.getCollateralLoanId(contracts.bayc.address, id);

      expect(await contracts.bayc.ownerOf(id)).eq(contracts.nftVault.address);
      expect(await contracts.stBayc.ownerOf(id)).eq(contracts.mockBendLendPool.address);
      expect(await contracts.mockBendLendPoolLoan.borrowerOf(nftLoanId)).eq(owner.address);
    }
  });

  it("testMultipleNftHasAuction", async () => {
    await contracts.weth.connect(owner).approve(contracts.mockBendLendPool.address, constants.MaxUint256);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.mockBendLendPool.address, true);
    await contracts.bayc.connect(owner).setApprovalForAll(contracts.lendingMigrator.address, true);

    baycTokenIds = [101, 102, 103];
    await mintNft(owner, contracts.bayc, baycTokenIds);

    let borrowAmounts = [makeBNWithDecimals(1, 18), makeBNWithDecimals(2, 18), makeBNWithDecimals(3, 18)];
    let totalBorrowAmounts = BigNumber.from(0);

    for (const [i, id] of baycTokenIds.entries()) {
      totalBorrowAmounts = totalBorrowAmounts.add(borrowAmounts[i]);
      await contracts.mockBendLendPool
        .connect(owner)
        .borrow(contracts.weth.address, borrowAmounts[i], contracts.bayc.address, id, owner.address, 0);
    }

    // set auction
    let bidFines = [BigNumber.from(0), BigNumber.from(0), BigNumber.from(0)];
    let totalBidFines = BigNumber.from(0);
    for (const [i, id] of baycTokenIds.entries()) {
      const nftLoanId = await contracts.mockBendLendPoolLoan.getCollateralLoanId(contracts.bayc.address, id);
      bidFines[i] = borrowAmounts[i].mul(5).div(100);
      totalBidFines = totalBidFines.add(bidFines[i]);
      await contracts.mockBendLendPoolLoan.setBidFine(nftLoanId, bidFines[i]);
    }

    const params = defaultAbiCoder.encode(
      ["address[]", "uint256[]"],
      [[contracts.bayc.address, contracts.bayc.address, contracts.bayc.address], baycTokenIds]
    );

    const totalFlashLoanAmout = totalBorrowAmounts.add(totalBidFines);

    await contracts.mockAaveLendPool.flashLoan(
      contracts.lendingMigrator.address,
      [contracts.weth.address],
      [totalFlashLoanAmout],
      [0],
      owner.address,
      params,
      0
    );

    for (const [, id] of baycTokenIds.entries()) {
      const nftLoanId = await contracts.mockBendLendPoolLoan.getCollateralLoanId(contracts.bayc.address, id);

      expect(await contracts.bayc.ownerOf(id)).eq(contracts.nftVault.address);
      expect(await contracts.stBayc.ownerOf(id)).eq(contracts.mockBendLendPool.address);
      expect(await contracts.mockBendLendPoolLoan.borrowerOf(nftLoanId)).eq(owner.address);
    }
  });
});
