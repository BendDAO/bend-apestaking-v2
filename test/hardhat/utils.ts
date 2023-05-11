/* eslint-disable node/no-extraneous-import */
/* eslint-disable @typescript-eslint/explicit-module-boundary-types */
/* eslint-disable @typescript-eslint/no-explicit-any */

import fc, { ShuffledSubarrayConstraints } from "fast-check";
import { ethers } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { MintableERC721 } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { advanceBlock, latest, increaseTo, increaseBy } from "./helpers/block-traveller";

export function makeBN18(num: any): BigNumber {
  return ethers.utils.parseUnits(num.toString(), 18);
}

export function makeBNWithDecimals(num: any, decimals: any): BigNumber {
  return ethers.utils.parseUnits(num.toString(), decimals);
}

export const getContract = async <ContractType extends Contract>(
  contractName: string,
  address: string
): Promise<ContractType> => (await ethers.getContractAt(contractName, address)) as ContractType;

export const mintNft = async (owner: SignerWithAddress, nft: MintableERC721, tokenIds: number[]): Promise<void> => {
  for (let id of tokenIds) {
    await nft.connect(owner).mint(id);
  }
};

const skipHourBlocks = async (tolerance: number) => {
  const currentTime = await latest();
  // skip hour blocks
  if (currentTime % 3600 >= 3600 - tolerance) {
    await increaseTo(Math.round(currentTime / 3600) * 3600 + 1);
    await advanceBlock();
  }
};

export const advanceHours = async (hours: number) => {
  await increaseBy(randomUint(3600, 3600 * hours));
  await advanceBlock();
  await skipHourBlocks(60);
};

export const randomUint = (min: number, max: number) => {
  return fc.sample(fc.integer({ min, max }), 1)[0];
};

export const shuffledSubarray = (originalArray: number[], constraints?: ShuffledSubarrayConstraints) => {
  return fc.sample(
    fc.shuffledSubarray(originalArray, constraints || { minLength: 1, maxLength: originalArray.length }),
    1
  )[0];
};

export const randomItem = (originalArray: number[]) => {
  return fc.sample(fc.constantFrom(...originalArray), 1)[0];
};

export async function deployContract<ContractType extends Contract>(
  contractName: string,
  args: any[],
  libraries?: { [libraryName: string]: string }
): Promise<ContractType> {
  // console.log("deployContract:", contractName, args, libraries);
  const instance = await (await ethers.getContractFactory(contractName, { libraries })).deploy(...args);
  return instance as ContractType;
}
