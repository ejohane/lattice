import path from "node:path";
import { copyFile, cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { AppDoctorOptions, AppInstallOptions, AppInstallResult, LatticeApp } from "./types";
import {
  readLatticeUserConfig,
  resolveLatticeConfigPath,
  resolveLatticeDataDir,
  writeLatticeUserConfig,
} from "./config";
import { ensureVault, exists } from "../vault";

const DEFAULT_REPO = "ejohane/lattice";
const RAYCAST_ARTIFACT = "lattice-raycast-extension";

export const raycastApp: LatticeApp = {
  id: "raycast",
  title: "Raycast Extension",
  description: "Fast Lattice capture and vault operations from Raycast.",
  install: installRaycastApp,
  doctor: doctorRaycastApp,
};

async function installRaycastApp(options: AppInstallOptions): Promise<AppInstallResult> {
  if (process.platform !== "darwin") {
    throw new Error("The Raycast app installer is only supported on macOS.");
  }

  const vaultPath = path.resolve(options.vaultPath);
  await ensureVault(vaultPath);

  const installRoot = path.resolve(
    options.installDir ?? path.join(resolveLatticeDataDir(), "apps", "raycast"),
  );
  const extensionPath = path.join(installRoot, "raycast-extension");
  const configPath = options.configPath
    ? resolveLatticeConfigPath({ configPath: options.configPath })
    : resolveLatticeConfigPath();
  const steps: string[] = [];
  const warnings: string[] = [];

  await rm(installRoot, { recursive: true, force: true });
  await mkdir(installRoot, { recursive: true });

  const localSource = options.sourceDir
    ? await resolveExplicitRaycastSource(options.sourceDir)
    : await findLocalRaycastSource();
  if (localSource) {
    await copyLocalRaycastSource(localSource, installRoot);
    steps.push(`Copied Raycast extension from ${localSource}`);
  } else {
    await installRaycastFromRelease({
      installRoot,
      version: options.version ?? "latest",
      repo: options.repo ?? DEFAULT_REPO,
      ...(options.baseUrl ? { baseUrl: options.baseUrl } : {}),
    });
    steps.push(`Downloaded Raycast extension artifact ${RAYCAST_ARTIFACT}.tar.gz`);
  }

  const latticePath = options.latticePath ?? await findLatticeExecutable();
  if (!latticePath) {
    warnings.push(
      "Could not find a lattice binary on PATH. Set the Raycast Lattice Path preference or reinstall with --lattice-path.",
    );
  }

  const config = await readLatticeUserConfig(configPath);
  await writeLatticeUserConfig(
    {
      ...config,
      lattice_path: latticePath ?? config.lattice_path,
      default_vault_path: vaultPath,
      apps: {
        ...config.apps,
        raycast: {
          extension_path: extensionPath,
          installed_at: new Date().toISOString(),
        },
      },
    },
    configPath,
  );
  steps.push(`Wrote Lattice app config to ${configPath}`);

  await run(["bun", "install", "--frozen-lockfile"], extensionPath);
  steps.push("Installed Raycast extension dependencies");
  await run(["bun", "run", "build"], extensionPath);
  steps.push("Built Raycast extension");

  if (options.importToRaycast !== false) {
    try {
      await startRaycastDevelopmentMode(extensionPath);
      steps.push("Started Raycast development mode to import the extension");
    } catch (error) {
      warnings.push(
        `Could not start Raycast development mode: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  return {
    app: "raycast",
    installed_path: extensionPath,
    config_path: configPath,
    steps,
    warnings,
  };
}

async function doctorRaycastApp(options: AppDoctorOptions) {
  const configPath = options.configPath
    ? resolveLatticeConfigPath({ configPath: options.configPath })
    : resolveLatticeConfigPath();
  const ok: string[] = [];
  const warnings: string[] = [];
  const errors: string[] = [];

  if (process.platform === "darwin") {
    ok.push("macOS platform");
    if (await exists("/Applications/Raycast.app")) {
      ok.push("Raycast.app exists");
    } else {
      warnings.push("Raycast.app was not found in /Applications.");
    }
  } else {
    errors.push("Raycast is only supported on macOS.");
  }

  if (await exists(configPath)) {
    ok.push(`config exists: ${configPath}`);
    const config = await readLatticeUserConfig(configPath);
    if (config.default_vault_path) {
      ok.push(`default vault: ${config.default_vault_path}`);
    } else {
      warnings.push("No default vault path is configured.");
    }
    if (config.lattice_path) {
      ok.push(`lattice path: ${config.lattice_path}`);
    } else {
      warnings.push("No lattice binary path is configured.");
    }
    if (config.apps.raycast?.extension_path) {
      const extensionPath = config.apps.raycast.extension_path;
      if (await exists(path.join(extensionPath, "package.json"))) {
        ok.push(`Raycast extension installed: ${extensionPath}`);
      } else {
        errors.push(`Raycast extension package is missing: ${extensionPath}`);
      }
    } else {
      warnings.push("Raycast app is not recorded as installed.");
    }
  } else {
    errors.push(`Missing Lattice app config: ${configPath}`);
  }

  return { app: "raycast", ok, warnings, errors };
}

async function findLocalRaycastSource(): Promise<string | undefined> {
  const candidates = [
    path.resolve(process.cwd(), "raycast-extension"),
    path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "raycast-extension"),
  ];

  for (const candidate of candidates) {
    if (await exists(path.join(candidate, "package.json"))) {
      return candidate;
    }
  }

  return undefined;
}

async function resolveExplicitRaycastSource(sourceDir: string): Promise<string> {
  const resolved = path.resolve(sourceDir);
  if (!(await exists(path.join(resolved, "package.json")))) {
    throw new Error(`Raycast source directory is missing package.json: ${resolved}`);
  }

  return resolved;
}

async function copyLocalRaycastSource(sourceDir: string, installRoot: string): Promise<void> {
  await copyTree(sourceDir, path.join(installRoot, "raycast-extension"), {
    exclude: new Set([
      "node_modules",
      ".raycast",
      "assets/icon-options",
      "raycast-env.d.ts",
    ]),
  });

  const repoRoot = path.dirname(sourceDir);
  const iconPath = path.join(repoRoot, "assets", "icon.svg");
  if (await exists(iconPath)) {
    await mkdir(path.join(installRoot, "assets"), { recursive: true });
    await copyFile(iconPath, path.join(installRoot, "assets", "icon.svg"));
  }
}

async function installRaycastFromRelease(options: {
  installRoot: string;
  version: string;
  repo: string;
  baseUrl?: string;
}): Promise<void> {
  const archiveName = `${RAYCAST_ARTIFACT}.tar.gz`;
  const checksumName = `${archiveName}.sha256`;
  const baseUrl = resolveDownloadBaseUrl(options);
  const tempDir = await mkdtemp(path.join(tmpdir(), "lattice-raycast-"));

  try {
    const archivePath = path.join(tempDir, archiveName);
    const checksumPath = path.join(tempDir, checksumName);
    await downloadToFile(`${baseUrl}/${archiveName}`, archivePath);
    await downloadToFile(`${baseUrl}/${checksumName}`, checksumPath);
    await verifyChecksum(archivePath, checksumPath);
    await run(["tar", "-xzf", archivePath, "-C", options.installRoot], process.cwd());
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

function resolveDownloadBaseUrl(options: {
  repo: string;
  version: string;
  baseUrl?: string | undefined;
}): string {
  if (options.baseUrl) {
    return options.baseUrl.replace(/\/+$/, "");
  }

  if (options.version === "latest") {
    return `https://github.com/${options.repo}/releases/latest/download`;
  }

  return `https://github.com/${options.repo}/releases/download/${options.version}`;
}

async function findLatticeExecutable(): Promise<string | undefined> {
  if (!process.argv[1]?.endsWith(".ts")) {
    return process.execPath;
  }

  const pathValue = process.env.PATH ?? "";
  for (const directory of pathValue.split(path.delimiter)) {
    const candidate = path.join(directory, "lattice");
    if (await exists(candidate)) {
      return candidate;
    }
  }

  return undefined;
}

async function startRaycastDevelopmentMode(extensionPath: string): Promise<void> {
  const child = Bun.spawn(["bun", "run", "dev"], {
    cwd: extensionPath,
    stdout: "ignore",
    stderr: "ignore",
  });

  await new Promise((resolve) => setTimeout(resolve, 1500));
  (child as { unref?: () => void }).unref?.();
}

async function run(args: string[], cwd: string, stdoutFile?: string): Promise<void> {
  const child = Bun.spawn(args, {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
  });
  const exitCode = await child.exited;
  const stdout = await new Response(child.stdout).text();
  const stderr = await new Response(child.stderr).text();
  if (exitCode !== 0) {
    throw new Error(`${args.join(" ")} failed with exit code ${exitCode}: ${stderr.trim()}`);
  }

  if (stdoutFile) {
    await writeFile(path.join(cwd, stdoutFile), stdout);
  }
}

async function downloadToFile(url: string, filePath: string): Promise<void> {
  if (url.startsWith("file://")) {
    await writeFile(filePath, await readFile(new URL(url)));
    return;
  }

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Download failed (${response.status}): ${url}`);
  }

  await writeFile(filePath, Buffer.from(await response.arrayBuffer()));
}

async function verifyChecksum(archivePath: string, checksumPath: string): Promise<void> {
  const expected = (await readFile(checksumPath, "utf8")).trim().split(/\s+/)[0]?.toLowerCase();
  if (!expected || !/^[a-f0-9]{64}$/.test(expected)) {
    throw new Error(`Invalid checksum file: ${checksumPath}`);
  }

  const actual = createHash("sha256")
    .update(await readFile(archivePath))
    .digest("hex");
  if (actual !== expected) {
    throw new Error(`Checksum mismatch for ${path.basename(archivePath)}`);
  }
}

async function copyTree(
  source: string,
  destination: string,
  options: { exclude?: Set<string> } = {},
): Promise<void> {
  await cp(source, destination, {
    recursive: true,
    filter: (sourcePath) => {
      const relative = path.relative(source, sourcePath);
      const normalized = relative.split(path.sep).join("/");
      const topLevel = normalized.split("/")[0];
      return (
        !normalized.endsWith(".raycast-dev.plist") &&
        (!topLevel || !options.exclude?.has(topLevel)) &&
        !Array.from(options.exclude ?? []).some((excluded) =>
          normalized === excluded || normalized.startsWith(`${excluded}/`),
        )
      );
    },
  });
}
