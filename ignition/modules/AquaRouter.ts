import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AquaRouter", (m) => {
  const account = m.getAccount(0);
  const owner = m.getParameter("owner", account);

  const aquaRouter = m.contract("AquaRouter", [owner]);

  return { aquaRouter };
});
