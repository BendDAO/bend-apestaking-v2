import { Contracts } from "../_setup";
import { makeStNftTest } from "./StNft.test";

makeStNftTest("StMAYC", (contracts: Contracts) => {
  return [contracts.stMayc, contracts.mayc];
});
