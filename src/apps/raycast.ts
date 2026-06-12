import { createHash } from "node:crypto";
import path from "node:path";
import { homedir, tmpdir } from "node:os";
import {
  chmod,
  copyFile,
  cp,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { AppDoctorOptions, AppInstallOptions, AppInstallResult, LatticeApp } from "./types";
import {
  readLatticeUserConfig,
  resolveLatticeConfigPath,
  resolveLatticeDataDir,
  writeLatticeUserConfig,
} from "./config";
import { ensureVault, exists } from "../vault";

const DEFAULT_REPO = "ejohane/lattice";
const RAYCAST_ARTIFACT = "lattice-raycast-extension-compiled";
const RAYCAST_EXTENSION_NAME = "lattice";

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

  if (options.sourceDir) {
    const sourceDir = await resolveExplicitRaycastSource(options.sourceDir);
    await copyLocalRaycastSource(sourceDir, installRoot);
    await buildLocalRaycastSource(extensionPath);
    steps.push(`Built Raycast extension from ${sourceDir}`);
  } else {
    await installCompiledRaycastFromRelease({
      installRoot,
      version: options.version ?? "latest",
      repo: options.repo ?? DEFAULT_REPO,
      ...(options.baseUrl ? { baseUrl: options.baseUrl } : {}),
    });
    steps.push(`Downloaded compiled Raycast extension artifact ${RAYCAST_ARTIFACT}.tar.gz`);
  }

  const latticePath = options.latticePath ?? await findLatticeExecutable();
  if (!latticePath) {
    warnings.push(
      "Could not find a lattice binary on PATH. Set the Raycast Lattice Path preference or reinstall with --lattice-path.",
    );
  }

  const raycastTargets =
    options.importToRaycast === false ? [] : await installCompiledRaycastExtension(extensionPath);
  for (const target of raycastTargets) {
    steps.push(`Installed compiled Raycast extension to ${target}`);
  }
  if (raycastTargets.length === 0 && options.importToRaycast !== false) {
    warnings.push(
      "Could not find a Raycast extension directory. Start Raycast once, then rerun the installer.",
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
          raycast_extension_paths: raycastTargets,
          installed_at: new Date().toISOString(),
        },
      },
    },
    configPath,
  );
  steps.push(`Wrote Lattice app config to ${configPath}`);

  return {
    app: "raycast",
    installed_path: raycastTargets[0] ?? extensionPath,
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
        ok.push(`managed Raycast extension exists: ${extensionPath}`);
      } else {
        errors.push(`Managed Raycast extension package is missing: ${extensionPath}`);
      }
    } else {
      warnings.push("Raycast app is not recorded as installed.");
    }

    const configuredTargets = config.apps.raycast?.raycast_extension_paths ?? [];
    for (const target of configuredTargets) {
      if (await exists(path.join(target, "package.json"))) {
        ok.push(`Raycast local extension exists: ${target}`);
      } else {
        errors.push(`Raycast local extension package is missing: ${target}`);
      }
    }
  } else {
    errors.push(`Missing Lattice app config: ${configPath}`);
  }

  return { app: "raycast", ok, warnings, errors };
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

async function buildLocalRaycastSource(extensionPath: string): Promise<void> {
  await run(["bun", "install", "--frozen-lockfile"], extensionPath);
  const compiledPath = `${extensionPath}-compiled`;
  await rm(compiledPath, { recursive: true, force: true });
  await run(
    ["bun", "run", "ray", "build", "--environment", "dist", "--output", compiledPath, "--non-interactive"],
    extensionPath,
  );
  await rm(extensionPath, { recursive: true, force: true });
  await mkdir(path.dirname(extensionPath), { recursive: true });
  await cp(compiledPath, extensionPath, { recursive: true });
  await rm(compiledPath, { recursive: true, force: true });
  await normalizeCompiledRaycastIcon(extensionPath);
}

async function installCompiledRaycastFromRelease(options: {
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

  const extensionPath = path.join(options.installRoot, "raycast-extension");
  if (!(await exists(path.join(extensionPath, "package.json")))) {
    throw new Error(`Raycast artifact did not contain raycast-extension/package.json`);
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

async function installCompiledRaycastExtension(extensionPath: string): Promise<string[]> {
  const targets = await resolveRaycastExtensionTargets();
  for (const target of targets) {
    await rm(target, { recursive: true, force: true });
    await mkdir(path.dirname(target), { recursive: true });
    await cp(extensionPath, target, { recursive: true });
    await chmodRaycastFiles(target);
  }
  return targets;
}

export async function resolveRaycastExtensionTargets(options: {
  homeDir?: string;
  extensionName?: string;
} = {}): Promise<string[]> {
  const home = options.homeDir ?? homedir();
  const extensionName = options.extensionName ?? RAYCAST_EXTENSION_NAME;
  const standardRoot = path.join(home, ".config", "raycast");
  const roots = [
    standardRoot,
    path.join(home, ".config", "raycast-x"),
  ];
  const existingRoots: string[] = [];

  for (const root of roots) {
    if (await exists(root) || await exists(path.join(root, "extensions"))) {
      existingRoots.push(root);
    }
  }

  const selectedRoots = existingRoots.length > 0 ? existingRoots : [standardRoot];
  return selectedRoots.map((root) => path.join(root, "extensions", extensionName));
}

async function chmodRaycastFiles(target: string): Promise<void> {
  const entries = await readdir(target, { withFileTypes: true });
  for (const entry of entries) {
    const entryPath = path.join(target, entry.name);
    if (entry.isDirectory()) {
      await chmodRaycastFiles(entryPath);
    } else if (entry.name.endsWith(".js")) {
      await chmod(entryPath, 0o644);
    }
  }
}

async function normalizeCompiledRaycastIcon(extensionPath: string): Promise<void> {
  const packagePath = path.join(extensionPath, "package.json");
  const manifest = JSON.parse(await readFile(packagePath, "utf8")) as { icon?: string };
  manifest.icon = "assets/icon.svg";
  const managedIconPath = path.join(path.dirname(extensionPath), "assets", "icon.svg");
  const sourceIconPath = (await exists(managedIconPath))
    ? managedIconPath
    : path.resolve("assets", "icon.svg");
  await mkdir(path.join(extensionPath, "assets"), { recursive: true });
  await copyFile(sourceIconPath, path.join(extensionPath, "assets", "icon.svg"));
  await writeFile(packagePath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
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

async function run(args: string[], cwd: string): Promise<void> {
  const child = Bun.spawn(args, {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
  });
  const exitCode = await child.exited;
  const stderr = await new Response(child.stderr).text();
  if (exitCode !== 0) {
    throw new Error(`${args.join(" ")} failed with exit code ${exitCode}: ${stderr.trim()}`);
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
