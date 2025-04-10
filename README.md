[![Build pass](https://github.com/BendDAO/bend-apestaking-v2-apechain/actions/workflows/tests.yaml/badge.svg)](https://github.com/BendDAO/bend-apestaking-v2-apechain/actions/workflows/tests.yaml)
[![codecov](https://codecov.io/gh/BendDAO/bend-apestaking-v2-apechain/branch/main/graph/badge.svg?token=lQiF4Ooeh5)](https://codecov.io/gh/BendDAO/bend-apestaking-v2-apechain)

```
######                       ######     #    #######
#     # ###### #    # #####  #     #   # #   #     #
#     # #      ##   # #    # #     #  #   #  #     #
######  #####  # #  # #    # #     # #     # #     #
#     # #      #  # # #    # #     # ####### #     #
#     # #      #   ## #    # #     # #     # #     #
######  ###### #    # #####  ######  #     # #######
```

# BendDAO ApeCoin Staking V2

## Description

This project contains all smart contracts used for the current BendDAO ApeCoin Staking V2 features. This includes:

- Pool to Pool Service Model;
- Coin holders deposit ApeCoin;
- NFT holders deposit BAYC/MAYC/BAKC;
- Holders can withdraw assets at any time;
- Holder can borrow ETH after staking;
- The rewards share ratio are determined by strategy contract;
- Bot will automatically do the pairing for the Coin and NFT;
- Bot will automatically do the claim rewards and compounding;

## Documentation

[Docs](https://docs.benddao.xyz/portal/)

## Audits

- [Verilog Solution](https://www.verilog.solutions/audits/benddao_ape_staking_v2/)

### Run tests

- TypeScript tests are included in the `test` folder at the root of this repo.
- Solidity tests are included in the `test` folder in the `contracts` folder.

```shell
yarn install
yarn test
```

### Run static analysis

```shell
# install only once
pip3 install slither-analyzer

slither .
```
