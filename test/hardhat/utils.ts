/* eslint-disable node/no-extraneous-import */
/* eslint-disable @typescript-eslint/explicit-module-boundary-types */
/* eslint-disable @typescript-eslint/no-explicit-any */

import fc from "fast-check";
import { ethers } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { MintableERC721 } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { advanceBlock, latest, increaseTo } from "./helpers/block-traveller";

export function makeBN18(num: any): BigNumber {
  return ethers.utils.parseUnits(num.toString(), 18);
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

export const skipHourBlocks = async (tolerance: number) => {
  const currentTime = await latest();
  // skip hour blocks
  if (currentTime % 3600 >= 3599 - tolerance) {
    await increaseTo(Math.round(currentTime / 3600) * 3600);
    await advanceBlock();
  }
};

export const randomUint = (min: number, max: number) => {
  return fc.sample(fc.integer({ min, max }), 1)[0];
};
