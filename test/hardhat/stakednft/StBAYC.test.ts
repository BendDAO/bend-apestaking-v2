import { Contracts } from "../_setup";
import { makeStNftTest } from "./StNft.test";

makeStNftTest("StBAYC", (contracts: Contracts) => {
  return [contracts.stBayc, contracts.bayc];
});
