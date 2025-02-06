import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "./generated/generated.ts",
  contracts: [],
  plugins: [
    foundry({
      include: [
        "ICreditFacadeV3_Extension.sol/**.json",
        "CreditAccountHelper.sol/**.json",
      ],
    }),
  ],
});