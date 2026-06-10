import { openVaultPath } from "./lib/open-path";

export default async function Command() {
  await openVaultPath("exports/packs");
}
