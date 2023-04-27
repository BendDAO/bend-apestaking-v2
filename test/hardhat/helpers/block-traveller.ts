import { BigNumber } from "ethers";
import { ethers, network } from "hardhat";

/**
 * Advance the state by one block
 */
export async function advanceBlock(): Promise<void> {
  await network.provider.send("evm_mine");
}

/**
 * Advance the block to the passed target block
 * @param targetBlock target block number
 * @dev If target block is lower/equal to current block, it throws an error
 */
export async function advanceBlockTo(targetBlock: number): Promise<void> {
  const currentBlock = await ethers.provider.getBlockNumber();
  if (targetBlock < currentBlock) {
    throw Error(`Target·block·#(${targetBlock})·is·lower·than·current·block·#(${currentBlock})`);
  }

  let numberBlocks = targetBlock - currentBlock;

  // hardhat_mine only can move by 256 blocks (256 in hex is 0x100)
  while (numberBlocks >= 256) {
    await network.provider.send("hardhat_mine", ["0x100"]);
    numberBlocks = numberBlocks - 256;
  }

  if (numberBlocks === 1) {
    await network.provider.send("evm_mine");
  } else if (numberBlocks === 15) {
    // Issue with conversion from hexString of 15 (0x0f instead of 0xF)
    await network.provider.send("hardhat_mine", ["0xF"]);
  } else {
    await network.provider.send("hardhat_mine", [BigNumber.from(numberBlocks).toHexString()]);
  }
}

/**
 * Advance the block time to target time
 * @param targetTime target time (epoch)
 * @dev If target time is lower/equal to current time, it throws an error
 */
export async function increaseTo(targetTime: number): Promise<void> {
  const currentTime = await latest();
  if (targetTime < currentTime) {
    throw Error(`Target time: (${targetTime}) is lower than current time: #(${currentTime})`);
  }

  await network.provider.send("evm_setNextBlockTimestamp", [BigNumber.from(targetTime).toHexString()]);
}

/**
 * Advance the block time
 * @param targetTime target time (epoch)
 * @dev If target time is lower/equal to current time, it throws an error
 */
export async function increaseBy(targetTime: number): Promise<void> {
  const currentTime = await latest();
  await network.provider.send("evm_setNextBlockTimestamp", [BigNumber.from(currentTime).add(targetTime).toHexString()]);
}

/**
 * Fetch the current block number
 */
export async function latest(): Promise<number> {
  return (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
}

/**
 * Start automine
 */
export async function pauseAutomine(): Promise<void> {
  await network.provider.send("evm_setAutomine", [false]);
}

/**
 * Resume automine
 */
export async function resumeAutomine(): Promise<void> {
  await network.provider.send("evm_setAutomine", [true]);
}
