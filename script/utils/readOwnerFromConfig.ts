import { readFileSync } from "node:fs";
import path from "node:path";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export function readOwnerFromConfig(chainId: number): string {
  const constantsPath = path.join(
    import.meta.dirname,
    "..",
    "..",
    "config",
    "constants.json",
  );
  const constants = JSON.parse(readFileSync(constantsPath, "utf8"));
  const owner: string | undefined = constants?.owner?.[chainId.toString()];

  if (owner === undefined || owner.toLowerCase() === ZERO_ADDRESS) {
    throw new Error(
      `OwnerAddressDoesNotExist: no non-zero owner for chain ${chainId} in config/constants.json`,
    );
  }

  return owner;
}
