import { Contracts } from "../_setup";
import { makeStNftTest } from "./StNft.test";

makeStNftTest("StBAKC", (contracts: Contracts) => {
  return [contracts.stBakc, contracts.bakc];
});
