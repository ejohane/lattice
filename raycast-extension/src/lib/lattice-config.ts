import { existsSync, readFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { getPreferences } from "./preferences";

interface LatticeUserConfig {
  lattice_path?: string;
  default_vault_path?: string;
}

export function resolveLatticePath(): string {
  const preferences = getPreferences();
  return preferences.latticePath?.trim() || readLatticeConfig().lattice_path || "lattice";
}

export function resolveVaultPath(): string {
  const preferences = getPreferences();
  const vaultPath = preferences.vaultPath?.trim() || readLatticeConfig().default_vault_path;
  if (!vaultPath) {
    throw new Error(
      "No Lattice vault is configured. Run `lattice apps install raycast --vault <path>` or set the Vault Path preference.",
    );
  }

  return vaultPath;
}

function readLatticeConfig(): LatticeUserConfig {
  for (const configPath of configCandidates()) {
    if (!existsSync(configPath)) {
      continue;
    }

    try {
      return JSON.parse(readFileSync(configPath, "utf8")) as LatticeUserConfig;
    } catch {
      return {};
    }
  }

  return {};
}

function configCandidates(): string[] {
  const explicit = process.env.LATTICE_CONFIG_PATH?.trim();
  if (explicit) {
    return [explicit];
  }

  return [
    path.join(os.homedir(), "Library", "Application Support", "Lattice", "config.json"),
    path.join(os.homedir(), ".config", "lattice", "config.json"),
  ];
}
