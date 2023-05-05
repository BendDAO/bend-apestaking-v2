import { Contracts } from "../setup";
import { makeStNftTest } from "./StNft.test";

makeStNftTest("StMAYC", (contracts: Contracts) => {
  return [contracts.stMayc, contracts.mayc];
});
