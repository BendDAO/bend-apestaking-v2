/* eslint-disable @typescript-eslint/no-explicit-any */
import { constants, Contract, ContractReceipt, ContractTransaction, Signer } from "ethers";
import { verifyEtherscanContract } from "./verification";
import { DRE, DB } from "./DRE";

export const waitForTx = async (tx: ContractTransaction): Promise<ContractReceipt> => await tx.wait(1);

export const registerContractInJsonDB = async (contractId: string, contractInstance: Contract): Promise<void> => {
  const currentNetwork = DRE.network.name;
  console.log(`\n*** ${contractId} ***\n`);
  console.log(`Network: ${currentNetwork}`);
  console.log(`tx: ${contractInstance.deployTransaction.hash}`);
  console.log(`contract address: ${contractInstance.address}`);
  console.log(`deployer address: ${contractInstance.deployTransaction.from}`);
  console.log(`gas price: ${contractInstance.deployTransaction.gasPrice}`);
  console.log(`gas used: ${contractInstance.deployTransaction.gasLimit}`);
  console.log(`\n******`);
  console.log();

  DB.set(contractId, {
    address: contractInstance.address,
    deployer: contractInstance.deployTransaction.from,
  }).write();
};

export const getContractAddressFromDB = async (id: string): Promise<string> => {
  const contractAtDb = DB.get(id).value();
  if (contractAtDb?.address) {
    return contractAtDb.address;
  }
  throw Error(`Missing contract address ${id} from local DB`);
};

export const getDeploySigner = async (): Promise<Signer> => (await getSigners())[0];

export const getSigners = async (): Promise<Signer[]> => {
  return await Promise.all(await DRE.ethers.getSigners());
};

export const getSignerByAddress = async (address: string): Promise<Signer> => {
  return await DRE.ethers.getSigner(address);
};

export const getSignersAddresses = async (): Promise<string[]> =>
  await Promise.all((await getSigners()).map((signer) => signer.getAddress()));

export const deployImplementation = async <ContractType extends Contract>(
  contractName: string,
  verify?: boolean,
  libraries?: { [libraryName: string]: string }
): Promise<ContractType> => {
  console.log("deploy", contractName, "with libraries:", libraries);
  const instance = await (await DRE.ethers.getContractFactory(contractName, { libraries }))
    .connect(await getDeploySigner())
    .deploy();
  console.log("Impl address:", instance.address);

  if (verify) {
    await verifyEtherscanContract(instance.address, []);
  }

  return instance as ContractType;
};

export const deployContract = async <ContractType extends Contract>(
  contractName: string,
  args: any[],
  verify?: boolean,
  dbKey?: string,
  libraries?: { [libraryName: string]: string }
): Promise<ContractType> => {
  dbKey = dbKey || contractName;
  console.log("deploy", dbKey);
  const instance = await (await DRE.ethers.getContractFactory(contractName, { libraries }))
    .connect(await getDeploySigner())
    .deploy(...args);

  await withSaveAndVerify(instance, dbKey, args, verify);
  return instance as ContractType;
};

export const deployProxyContract = async <ContractType extends Contract>(
  contractName: string,
  args: any[],
  verify?: boolean,
  dbKey?: string,
  libraries?: { [libraryName: string]: string }
): Promise<ContractType> => {
  dbKey = dbKey || contractName;
  console.log("deploy", dbKey);
  let hasLib = false;
  if (libraries) {
    hasLib = true;
  }
  const factory = await DRE.ethers.getContractFactory(contractName, { libraries });
  const instance = await DRE.upgrades.deployProxy(factory, args, {
    timeout: 0,
    unsafeAllowLinkedLibraries: hasLib,
  });
  await withSaveAndVerify(instance, dbKey, args, verify);
  return instance as ContractType;
};

export const deployProxyContractWithoutInit = async <ContractType extends Contract>(
  contractName: string,
  args: any[],
  verify?: boolean,
  dbKey?: string
): Promise<ContractType> => {
  dbKey = dbKey || contractName;
  console.log("deploy", dbKey);
  const factory = await DRE.ethers.getContractFactory(contractName);
  const instance = await DRE.upgrades.deployProxy(factory, args, {
    timeout: 0,
    initializer: false,
  });
  await withSaveAndVerify(instance, dbKey, args, verify);
  return instance as ContractType;
};

export const withSaveAndVerify = async (
  instance: Contract,
  id: string,
  args: (string | string[] | any)[],
  verify?: boolean
): Promise<Contract> => {
  await waitForTx(instance.deployTransaction);
  await registerContractInJsonDB(id, instance);
  if (verify) {
    let impl = constants.AddressZero;
    try {
      impl = await DRE.upgrades.erc1967.getImplementationAddress(instance.address);
    } catch (error) {
      impl = constants.AddressZero;
    }
    if (impl !== constants.AddressZero) {
      await verifyEtherscanContract(impl, []);
    } else {
      await verifyEtherscanContract(instance.address, args);
    }
  }
  return instance;
};

export const getChainId = async (): Promise<number> => {
  return (await DRE.ethers.provider.getNetwork()).chainId;
};

export const getContract = async <ContractType extends Contract>(
  contractName: string,
  address: string
): Promise<ContractType> => (await DRE.ethers.getContractAt(contractName, address)) as ContractType;

export const getContractFromDB = async <ContractType extends Contract>(id: string): Promise<ContractType> => {
  return getContract(id, await getContractAddressFromDB(id));
};
