import { describe, expect, test } from "bun:test";
import os from "node:os";
import path from "node:path";
import { mkdir } from "node:fs/promises";
import {
  readLatticeUserConfig,
  resolveLatticeConfigPath,
  resolveLatticeDataDir,
  writeLatticeUserConfig,
} from "../src/apps/config";
import { getApp, listApps } from "../src/apps/registry";
import { resolveRaycastExtensionTargets } from "../src/apps/raycast";

describe("app registry", () => {
  test("lists Raycast as an installable app", () => {
    expect(listApps().map((app) => app.id)).toContain("raycast");
    expect(getApp("raycast").title).toBe("Raycast Extension");
  });

  test("rejects unknown apps", () => {
    expect(() => getApp("missing")).toThrow("Unknown app: missing");
  });
});

describe("lattice app config", () => {
  test("resolves platform-specific config and data paths", () => {
    expect(
      resolveLatticeConfigPath({
        platform: "darwin",
        homeDir: "/Users/example",
      }),
    ).toBe("/Users/example/Library/Application Support/Lattice/config.json");
    expect(
      resolveLatticeDataDir({
        platform: "linux",
        homeDir: "/home/example",
      }),
    ).toBe("/home/example/.local/share/lattice");
  });

  test("writes and reads user app config", async () => {
    const root = await tempRoot();
    const configPath = path.join(root, "config.json");

    await writeLatticeUserConfig(
      {
        schema_version: 1,
        lattice_path: "/usr/local/bin/lattice",
        default_vault_path: "/tmp/LatticeVault",
        apps: {
          raycast: {
            extension_path: "/tmp/lattice-raycast/raycast-extension",
            raycast_extension_paths: ["/tmp/raycast/extensions/lattice"],
            installed_at: "2026-06-09T10:00:00.000Z",
          },
        },
      },
      configPath,
    );

    expect(await readLatticeUserConfig(configPath)).toEqual({
      schema_version: 1,
      lattice_path: "/usr/local/bin/lattice",
      default_vault_path: "/tmp/LatticeVault",
      apps: {
        raycast: {
          extension_path: "/tmp/lattice-raycast/raycast-extension",
          raycast_extension_paths: ["/tmp/raycast/extensions/lattice"],
          installed_at: "2026-06-09T10:00:00.000Z",
        },
      },
    });
  });
});

describe("Raycast extension targets", () => {
  test("defaults to the standard Raycast config when none exist", async () => {
    const root = await tempRoot();
    await expect(resolveRaycastExtensionTargets({ homeDir: root })).resolves.toEqual([
      path.join(root, ".config", "raycast", "extensions", "lattice"),
    ]);
  });

  test("uses existing Raycast config roots", async () => {
    const root = await tempRoot();
    await mkdir(path.join(root, ".config", "raycast-x"), { recursive: true });

    await expect(resolveRaycastExtensionTargets({ homeDir: root })).resolves.toEqual([
      path.join(root, ".config", "raycast-x", "extensions", "lattice"),
    ]);
  });
});

async function tempRoot(): Promise<string> {
  const root = path.join(os.tmpdir(), `lattice-app-test-${crypto.randomUUID()}`);
  await mkdir(root, { recursive: true });
  return root;
}
