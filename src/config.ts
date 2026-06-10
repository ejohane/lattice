import path from "node:path";
import { DEFAULT_CONFIG, AppConfig, AppConfigSchema } from "./types";

export function resolveVaultPath(vault?: string): string {
  const explicit = vault?.trim() || process.env.LATTICE_VAULT_PATH?.trim();
  if (explicit) {
    return path.resolve(explicit);
  }

  return path.resolve(process.cwd(), "LatticeVault");
}

export function mergeConfig(input: unknown): AppConfig {
  if (!input || typeof input !== "object") {
    return DEFAULT_CONFIG;
  }

  const partial = input as Partial<AppConfig>;
  return AppConfigSchema.parse({
    protocol_version: 1,
    llm: {
      provider: partial.llm?.provider ?? DEFAULT_CONFIG.llm.provider,
      model: partial.llm?.model ?? DEFAULT_CONFIG.llm.model,
      temperature: partial.llm?.temperature ?? DEFAULT_CONFIG.llm.temperature,
    },
    capture: {
      screenshots_default:
        partial.capture?.screenshots_default ??
        DEFAULT_CONFIG.capture.screenshots_default,
    },
  });
}
