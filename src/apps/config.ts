import path from "node:path";
import { homedir } from "node:os";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { z } from "zod";
import { exists } from "../vault";

export const LatticeUserConfigSchema = z.object({
  schema_version: z.literal(1),
  lattice_path: z.string().optional(),
  default_vault_path: z.string().optional(),
  apps: z
    .object({
      raycast: z
        .object({
          extension_path: z.string(),
          installed_at: z.string(),
        })
        .optional(),
    })
    .default({}),
});

export type LatticeUserConfig = z.infer<typeof LatticeUserConfigSchema>;

export function resolveLatticeConfigPath(options: {
  platform?: NodeJS.Platform;
  homeDir?: string;
  configPath?: string;
} = {}): string {
  if (options.configPath) {
    return path.resolve(options.configPath);
  }

  if (process.env.LATTICE_CONFIG_PATH?.trim()) {
    return path.resolve(process.env.LATTICE_CONFIG_PATH.trim());
  }

  const platform = options.platform ?? process.platform;
  const home = options.homeDir ?? homedir();
  if (platform === "darwin") {
    return path.join(home, "Library", "Application Support", "Lattice", "config.json");
  }

  return path.join(home, ".config", "lattice", "config.json");
}

export function resolveLatticeDataDir(options: {
  platform?: NodeJS.Platform;
  homeDir?: string;
  dataDir?: string;
} = {}): string {
  if (options.dataDir) {
    return path.resolve(options.dataDir);
  }

  if (process.env.LATTICE_DATA_DIR?.trim()) {
    return path.resolve(process.env.LATTICE_DATA_DIR.trim());
  }

  const platform = options.platform ?? process.platform;
  const home = options.homeDir ?? homedir();
  if (platform === "darwin") {
    return path.join(home, "Library", "Application Support", "Lattice");
  }

  return path.join(home, ".local", "share", "lattice");
}

export async function readLatticeUserConfig(
  configPath = resolveLatticeConfigPath(),
): Promise<LatticeUserConfig> {
  if (!(await exists(configPath))) {
    return { schema_version: 1, apps: {} };
  }

  return LatticeUserConfigSchema.parse(JSON.parse(await readFile(configPath, "utf8")));
}

export async function writeLatticeUserConfig(
  config: LatticeUserConfig,
  configPath = resolveLatticeConfigPath(),
): Promise<void> {
  await mkdir(path.dirname(configPath), { recursive: true });
  await writeFile(
    configPath,
    `${JSON.stringify(LatticeUserConfigSchema.parse(config), null, 2)}\n`,
    "utf8",
  );
}
