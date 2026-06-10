import path from "node:path";
import { access } from "node:fs/promises";
import { open, showToast, Toast } from "@raycast/api";
import { getPreferences } from "./preferences";
import { runCli } from "./run-cli";

export async function openVaultPath(relativePath = ""): Promise<void> {
  const preferences = getPreferences();
  const target = path.join(preferences.vaultPath, relativePath);
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Opening Lattice",
    message: relativePath || preferences.vaultPath,
  });

  try {
    await runCli(["init"]);
    await access(target);
    await open(target);
    toast.style = Toast.Style.Success;
    toast.title = "Opened Lattice";
    toast.message = relativePath || preferences.vaultPath;
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = "Could not open Lattice folder";
    toast.message = error instanceof Error ? error.message : String(error);
  }
}
