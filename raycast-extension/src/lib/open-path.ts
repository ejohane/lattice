import path from "node:path";
import { open, showToast, Toast } from "@raycast/api";
import { getPreferences } from "./preferences";

export async function openVaultPath(relativePath = ""): Promise<void> {
  const preferences = getPreferences();
  const target = path.join(preferences.vaultPath, relativePath);
  await open(target);
  await showToast({
    style: Toast.Style.Success,
    title: "Opened Lattice",
    message: relativePath || preferences.vaultPath,
  });
}
