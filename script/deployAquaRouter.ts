import hre from "hardhat";
import aquaRouterModule from "../ignition/modules/AquaRouter.js";
import { readOwnerFromConfig } from "./utils/readOwnerFromConfig.js";

const connection = await hre.network.create();

const chainId = Number(
  await connection.provider.request({ method: "eth_chainId" }),
);

const ownerAddress = readOwnerFromConfig(chainId);

const { aquaRouter } = await connection.ignition.deploy(aquaRouterModule, {
  parameters: {
    AquaRouter: {
      owner: ownerAddress,
    },
  },
  displayUi: true,
});

console.log(`\nAquaRouter deployed at ${aquaRouter.address}`);
