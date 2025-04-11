export enum Network {
  apechain = "apechain",
  curtis = "curtis",
}

export interface Params<T> {
  [Network.apechain]: T;
  [Network.curtis]: T;
}

export const getParams = <T>({ apechain, curtis }: Params<T>, network: string): T => {
  network = Network[network as keyof typeof Network];
  switch (network) {
    case Network.curtis:
      return curtis;
    case Network.apechain:
      return apechain;
    default:
      return curtis;
  }
};

const INFURA_KEY = process.env.INFURA_KEY || "";
const ALCHEMY_KEY = process.env.ALCHEMY_KEY || "";

export const NETWORKS_RPC_URL: Params<string> = {
  [Network.apechain]: "https://rpc.apechain.com/http",
  [Network.curtis]: "https://curtis.rpc.caldera.xyz/http",
};

export const FEE: Params<string> = {
  [Network.apechain]: "400",
  [Network.curtis]: "400",
};

export const FEE_RECIPIENT: Params<string> = {
  [Network.apechain]: "0xfa67Ee32DAc2F1202Bc514e5D44CDF512a027a05",
  [Network.curtis]: "0xafF5C36642385b6c7Aaf7585eC785aB2316b5db6",
};

export const WAPE_COIN: Params<string> = {
  [Network.apechain]: "0x48b62137EdfA95a428D35C09E44256a739F6B557",
  [Network.curtis]: "0x647dc527Bd7dFEE4DD468cE6fC62FC50fa42BD8b",
};

export const BEACON: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "0x554309B0888c37139D6E31aBAe30B4502915B5DB",
};

export const APE_STAKING: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "0x3BD0A71D39E67fc49D5A6645550f2bc95F5cb398",
};

export const BAYC: Params<string> = {
  [Network.apechain]: "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d",
  [Network.curtis]: "0xE15A78992dd4a9d6833eA7C9643650d3b0a2eD2B",
};

export const MAYC: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "0x28cCcd47Aa3FFb42D77e395Fba7cdAcCeA884d5A",
};

export const BAKC: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "0xD0ff8ae7E3D9591605505D3db9C33b96c4809CDC",
};

export const DELEAGATE_CASH: Params<string> = {
  [Network.apechain]: "0x0000000000000000000000000000000000000000",
  [Network.curtis]: "0x0000000000000000000000000000000000000000",
};

export const BNFT_REGISTRY: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "0xc31078cC745daE8f577EdBa2803405CE571cb9f8",
};

export const AAVE_ADDRESS_PROVIDER: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "",
};

export const BEND_ADDRESS_PROVIDER: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "",
};

export const BAYC_REWARDS_SHARE_RATIO: Params<string> = {
  [Network.apechain]: "5000",
  [Network.curtis]: "5000",
};

export const MAYC_REWARDS_SHARE_RATIO: Params<string> = {
  [Network.apechain]: "5000",
  [Network.curtis]: "5000",
};

export const BAKC_REWARDS_SHARE_RATIO: Params<string> = {
  [Network.apechain]: "5000",
  [Network.curtis]: "5000",
};

export const STAKER_MANAGER_V1: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "",
};

export const COIN_POOL_V1: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "",
};

export const BENDV2_ADDRESS_PROVIDER: Params<string> = {
  [Network.apechain]: "",
  [Network.curtis]: "0x0000000000000000000000000000000000000000",
};
