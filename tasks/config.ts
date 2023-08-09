export enum Network {
  goerli = "goerli",
  mainnet = "mainnet",
}

export interface Params<T> {
  [Network.goerli]: T;
  [Network.mainnet]: T;
}

export const getParams = <T>({ goerli, mainnet }: Params<T>, network: string): T => {
  network = Network[network as keyof typeof Network];
  switch (network) {
    case Network.goerli:
      return goerli;
    case Network.mainnet:
      return mainnet;
    default:
      return goerli;
  }
};

const INFURA_KEY = process.env.INFURA_KEY || "";
const ALCHEMY_KEY = process.env.ALCHEMY_KEY || "";

export const NETWORKS_RPC_URL: Params<string> = {
  [Network.goerli]: ALCHEMY_KEY
    ? `https://eth-goerli.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://goerli.infura.io/v3/${INFURA_KEY}`,
  [Network.mainnet]: ALCHEMY_KEY
    ? `https://eth-mainnet.alchemyapi.io/v2/${ALCHEMY_KEY}`
    : `https://mainnet.infura.io/v3/${INFURA_KEY}`,
};

export const FEE: Params<string> = {
  [Network.goerli]: "400",
  [Network.mainnet]: "400",
};

export const FEE_RECIPIENT: Params<string> = {
  [Network.goerli]: "0x10855337e1b0D2d11F8f59Ba4b04EC8792A58B61",
  [Network.mainnet]: "0x472FcC65Fab565f75B1e0E861864A86FE5bcEd7B",
};

export const APE_COIN: Params<string> = {
  [Network.goerli]: "0x701ca86a355dA5E32b70a9c7e8967B4DFaa735dB",
  [Network.mainnet]: "0x4d224452801ACEd8B2F0aebE155379bb5D594381",
};

export const APE_STAKING: Params<string> = {
  [Network.goerli]: "0xa1d0e0Ac6D1300F47caC9083b23D07F62bB1F833",
  [Network.mainnet]: "0x5954aB967Bc958940b7EB73ee84797Dc8a2AFbb9",
};

export const BAYC: Params<string> = {
  [Network.goerli]: "0x30d190032A34d6151073a7DB8793c01Aa05987ec",
  [Network.mainnet]: "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d",
};

export const MAYC: Params<string> = {
  [Network.goerli]: "0x15596C27900e12A9cfC301248E21888751f61c19",
  [Network.mainnet]: "0x60E4d786628Fea6478F785A6d7e704777c86a7c6",
};

export const BAKC: Params<string> = {
  [Network.goerli]: "0x49EdA925C67387b4597F4b41817Aaade0542EeD5",
  [Network.mainnet]: "0xba30E5F9Bb24caa003E9f2f0497Ad287FDF95623",
};

export const DELEAGATE_CASH: Params<string> = {
  [Network.goerli]: "0x00000000000076A84feF008CDAbe6409d2FE638B",
  [Network.mainnet]: "0x00000000000076A84feF008CDAbe6409d2FE638B",
};

export const BNFT_REGISTRY: Params<string> = {
  [Network.goerli]: "0x37A76Db446bDB3EF1b73112a8D5E6868de06464f",
  [Network.mainnet]: "0x79d922DD382E42A156bC0A354861cDBC4F09110d",
};

export const WETH: Params<string> = {
  [Network.goerli]: "0xb4fbf271143f4fbf7b91a5ded31805e42b2208d6",
  [Network.mainnet]: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
};

export const AAVE_ADDRESS_PROVIDER: Params<string> = {
  [Network.goerli]: "0x94a675Fa2eFe076E99C126be1Bc80aedf4684190",
  [Network.mainnet]: "0xb53c1a33016b2dc2ff3653530bff1848a515c8c5",
};

export const BEND_ADDRESS_PROVIDER: Params<string> = {
  [Network.goerli]: "0x1cba0A3e18be7f210713c9AC9FE17955359cC99B",
  [Network.mainnet]: "0x24451f47caf13b24f4b5034e1df6c0e401ec0e46",
};

export const BAYC_REWARDS_SHARE_RATIO: Params<string> = {
  [Network.goerli]: "5000",
  [Network.mainnet]: "5000",
};

export const MAYC_REWARDS_SHARE_RATIO: Params<string> = {
  [Network.goerli]: "5000",
  [Network.mainnet]: "5000",
};

export const BAKC_REWARDS_SHARE_RATIO: Params<string> = {
  [Network.goerli]: "5000",
  [Network.mainnet]: "5000",
};

export const STAKER_MANAGER_V1: Params<string> = {
  [Network.goerli]: "0x3d90c2Eb0f7919c843C2a26Af32B1b0f3033d54b",
  [Network.mainnet]: "0xDAFCe4AcC2703A24F29d1321AdAADF5768F54642",
};

export const COIN_POOL_V1: Params<string> = {
  [Network.goerli]: "0x780592BEBaC01FAe7e1040E14C41F921C0A5c789",
  [Network.mainnet]: "0xEB3837c611fb2C5550F816f227D85262f0d04A52",
};
