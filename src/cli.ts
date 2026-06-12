#!/usr/bin/env bun
import { Command } from "commander";
import path from "node:path";
import { copyFile, mkdir, readdir, stat } from "node:fs/promises";
import { mergeConfig, normalizeVaultName, resolveVaultPath } from "./config";
import { createCapture } from "./capture/capture";
import { listIngested, listPending, markIngested } from "./queue";
import { QueueEntry, VaultPaths } from "./types";
import { timestampForFilename } from "./time";
import {
  ensureVault,
  exists,
  getVaultPaths,
  installBundledSkills,
  readJsonIfExists,
  writeJson,
} from "./vault";
import { updateLattice } from "./update";
import { getApp, listApps } from "./apps/registry";

const program = new Command();

program
  .name("lattice")
  .description("Local-first context capture protocol for agent-maintained wikis.")
  .option("--vault <path>", "Vault path. Defaults to LATTICE_VAULT_PATH or ./LatticeVault.");

program
  .command("init")
  .description("Create the vault folder structure.")
  .option("--name <name>", "Human-readable vault name.")
  .action(async (options) => {
    const root = resolveVaultPath(program.opts().vault);
    const vaultName = resolveVaultNameOption(options.name);
    await ensureVault(root, vaultName ? { vaultName } : {});
    console.log(`Initialized vault: ${root}`);
  });

program
  .command("capture")
  .description("Capture a note into the local vault.")
  .option("--body <text>", "Note body.")
  .option("--stdin", "Read note body from stdin.")
  .option("--source <source>", "Capture source.", "cli")
  .option("--json", "Print machine-readable JSON.")
  .option("--screenshot", "Capture a screenshot.", true)
  .option("--no-screenshot", "Skip screenshot capture.")
  .action(async (options) => {
    const root = resolveVaultPath(program.opts().vault);
    const paths = await ensureVault(root);
    const body = await resolveBody(options);
    if (!body.trim()) {
      throw new Error("Cannot save an empty capture.");
    }

    const capture = await createCapture({
      paths,
      body: body.trim(),
      source: options.source,
      screenshot: options.screenshot,
    });

    if (options.json) {
      console.log(JSON.stringify(capture, null, 2));
    } else {
      console.log(`Saved ${capture.id}`);
    }
  });

program
  .command("pending")
  .description("List captures waiting for external agent ingestion.")
  .option("--json", "Print machine-readable JSON.")
  .action(listPendingCommand);

program
  .command("list")
  .description("Alias for pending.")
  .option("--json", "Print machine-readable JSON.")
  .action(listPendingCommand);

program
  .command("mark-ingested")
  .description("Move pending capture IDs into the ingested queue.")
  .argument("<captureIds...>", "Capture IDs to mark ingested.")
  .option("--agent <name>", "Agent or harness name.", "agent")
  .option("--json", "Print machine-readable JSON.")
  .action(async (captureIds: string[], options) => {
    const root = resolveVaultPath(program.opts().vault);
    const paths = await ensureVault(root);
    const ids = captureIds.map((id) => id.trim()).filter(Boolean);
    if (ids.length === 0) {
      throw new Error("Provide at least one capture ID.");
    }

    const result = await markIngested({
      paths,
      captureIds: ids,
      agent: options.agent,
    });

    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
    } else if (result.missing.length > 0) {
      console.log(`Not pending: ${result.missing.join(", ")}`);
    } else {
      console.log(`Marked ${result.ingested.length} capture(s) ingested.`);
    }

    if (result.missing.length > 0) {
      process.exitCode = 1;
    }
  });

const skillsCommand = program
  .command("skills")
  .description("Manage bundled vault skills.");

skillsCommand
  .command("install")
  .description("Install bundled Lattice skills into the vault.")
  .option("--force", "Overwrite existing skill files.")
  .option("--json", "Print machine-readable JSON.")
  .action(async (options) => {
    const root = resolveVaultPath(program.opts().vault);
    const paths = await ensureVault(root, { installSkills: false });
    const result = await installBundledSkills(paths, {
      overwrite: options.force,
    });

    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    const action = options.force ? "Installed or updated" : "Installed";
    console.log(`${action} ${result.installed.length} skill file(s).`);
    if (result.skipped.length > 0) {
      console.log(`Skipped ${result.skipped.length} existing skill file(s).`);
    }
  });

program
  .command("doctor")
  .description("Check vault layout and queue readability.")
  .option("--json", "Print machine-readable JSON.")
  .action(async (options) => {
    const root = resolveVaultPath(program.opts().vault);
    const result = await doctorVault(root);

    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      for (const line of result.ok) {
        console.log(`ok: ${line}`);
      }
      for (const line of result.warnings) {
        console.log(`warning: ${line}`);
      }
      for (const line of result.errors) {
        console.log(`error: ${line}`);
      }
      console.log(
        result.errors.length === 0
          ? "Vault doctor passed."
          : "Vault doctor found errors.",
      );
    }

    if (result.errors.length > 0) {
      process.exitCode = 1;
    }
  });

program
  .command("pack")
  .description("Create a portable pack of pending raw captures and skills.")
  .option("--json", "Print machine-readable JSON.")
  .action(async (options) => {
    const root = resolveVaultPath(program.opts().vault);
    const paths = await ensureVault(root);
    const result = await createPendingPack(paths);
    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`Pack: ${path.relative(root, result.path)}`);
      console.log(`Captures: ${result.capture_count}`);
    }
  });

program
  .command("update")
  .description("Update the installed lattice binary from GitHub release artifacts.")
  .option("--version <tag>", "Release tag to install. Defaults to latest.", "latest")
  .option("--repo <owner/name>", "GitHub repository to download releases from.", "ejohane/lattice")
  .option("--install-dir <path>", "Install into this directory instead of replacing the running binary.")
  .option("--binary-name <name>", "Installed binary name when --install-dir is used.", "lattice")
  .option("--base-url <url>", "Release artifact base URL. Intended for mirrors and tests.")
  .option("--json", "Print machine-readable JSON.")
  .action(async (options) => {
    const result = await updateLattice({
      version: options.version,
      repo: options.repo,
      installDir: options.installDir,
      binaryName: options.binaryName,
      baseUrl: options.baseUrl,
    });

    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    console.log(`Updated lattice: ${result.installedPath}`);
    console.log(`Artifact: ${result.artifact}`);
    console.log(`Version: ${result.version}`);
  });

const appsCommand = program
  .command("apps")
  .description("Install and inspect Lattice capture apps.");

appsCommand
  .command("list")
  .description("List installable Lattice apps.")
  .option("--json", "Print machine-readable JSON.")
  .action((options) => {
    const apps = listApps().map((app) => ({
      id: app.id,
      title: app.title,
      description: app.description,
    }));

    if (options.json) {
      console.log(JSON.stringify(apps, null, 2));
      return;
    }

    for (const app of apps) {
      console.log(`${app.id}\t${app.title}\t${app.description}`);
    }
  });

appsCommand
  .command("install")
  .description("Install a Lattice app.")
  .argument("<app>", "App to install, for example: raycast.")
  .option("--version <tag>", "Release tag to install. Defaults to latest.", "latest")
  .option("--repo <owner/name>", "GitHub repository to download releases from.", "ejohane/lattice")
  .option("--base-url <url>", "Release artifact base URL. Intended for mirrors and tests.")
  .option("--source <path>", "Build and install app assets from a local source directory.")
  .option("--install-dir <path>", "Install managed app assets into this directory.")
  .option("--lattice-path <path>", "Lattice binary path for the app to call.")
  .option("--config <path>", "Write/read Lattice app config at this path.")
  .option("--no-import", "Skip installing into Raycast's local extension directory.")
  .option("--json", "Print machine-readable JSON.")
  .action(async (appId: string, options) => {
    const root = resolveVaultPath(program.opts().vault);
    const result = await getApp(appId).install({
      appId,
      vaultPath: root,
      version: options.version,
      repo: options.repo,
      baseUrl: options.baseUrl,
      sourceDir: options.source,
      installDir: options.installDir,
      latticePath: options.latticePath,
      configPath: options.config,
      importToRaycast: options.import,
    });

    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    console.log(`Installed ${result.app}: ${result.installed_path}`);
    console.log(`Config: ${result.config_path}`);
    for (const step of result.steps) {
      console.log(`ok: ${step}`);
    }
    for (const warning of result.warnings) {
      console.log(`warning: ${warning}`);
    }
  });

appsCommand
  .command("doctor")
  .description("Check a Lattice app installation.")
  .argument("<app>", "App to check, for example: raycast.")
  .option("--config <path>", "Read Lattice app config at this path.")
  .option("--json", "Print machine-readable JSON.")
  .action(async (appId: string, options) => {
    const result = await getApp(appId).doctor({
      appId,
      configPath: options.config,
    });

    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
      return;
    }

    for (const line of result.ok) {
      console.log(`ok: ${line}`);
    }
    for (const line of result.warnings) {
      console.log(`warning: ${line}`);
    }
    for (const line of result.errors) {
      console.log(`error: ${line}`);
    }

    if (result.errors.length > 0) {
      process.exitCode = 1;
    }
  });

async function resolveBody(options: {
  body?: string;
  stdin?: boolean;
}): Promise<string> {
  if (options.stdin) {
    return Bun.stdin.text();
  }

  if (options.body !== undefined) {
    return options.body;
  }

  throw new Error("Provide --body or --stdin.");
}

function resolveVaultNameOption(name?: string): string | undefined {
  if (name === undefined) {
    return undefined;
  }

  const vaultName = normalizeVaultName(name);
  if (!vaultName) {
    throw new Error("Vault name cannot be empty.");
  }

  return vaultName;
}

async function listPendingCommand(options: { json?: boolean }): Promise<void> {
  const root = resolveVaultPath(program.opts().vault);
  const paths = await ensureVault(root);
  const pending = await listPending(paths);

  if (options.json) {
    console.log(JSON.stringify(pending, null, 2));
    return;
  }

  if (pending.length === 0) {
    console.log("No pending captures.");
    return;
  }

  for (const entry of pending) {
    console.log(
      [
        entry.capture_id,
        entry.local_date,
        entry.source,
        entry.raw_capture_path,
      ].join("\t"),
    );
  }
}

async function doctorVault(root: string): Promise<{
  root: string;
  ok: string[];
  warnings: string[];
  errors: string[];
}> {
  const paths = getVaultPaths(root);
  const ok: string[] = [];
  const warnings: string[] = [];
  const errors: string[] = [];

  const directories = [
    paths.raw,
    paths.captures,
    paths.screenshots,
    paths.queue,
    paths.wiki,
    paths.wikiPages,
    paths.skills,
    paths.packs,
  ];
  for (const directory of directories) {
    if (await isDirectory(directory)) {
      ok.push(`${path.relative(root, directory) || "."}/`);
    } else {
      errors.push(`Missing directory: ${path.relative(root, directory)}`);
    }
  }

  const files = [
    path.join(root, "AGENTS.md"),
    paths.config,
    path.join(paths.wiki, "index.md"),
    path.join(paths.wiki, "log.md"),
    path.join(paths.skills, "AGENTS.md"),
    path.join(paths.skills, "ingest-captures.md"),
    path.join(paths.skills, "maintain-wiki.md"),
    path.join(paths.skills, "answer-from-wiki.md"),
    path.join(paths.skills, "lint-wiki.md"),
  ];
  for (const filePath of files) {
    if (await exists(filePath)) {
      ok.push(path.relative(root, filePath));
    } else {
      errors.push(`Missing file: ${path.relative(root, filePath)}`);
    }
  }

  if (await exists(paths.config)) {
    mergeConfig(await readJsonIfExists(paths.config));
    ok.push("config parses");
  }

  try {
    const pending = await listPending(paths);
    const ingested = await listIngested(paths);
    ok.push(`${pending.length} pending capture(s) parse`);
    ok.push(`${ingested.length} ingested capture(s) parse`);
  } catch (error) {
    errors.push(`Queue parse failed: ${error instanceof Error ? error.message : String(error)}`);
  }

  if (!(await exists(paths.rawLog))) {
    warnings.push("raw/log.jsonl does not exist yet");
  }

  return { root, ok, warnings, errors };
}

async function createPendingPack(paths: VaultPaths): Promise<{
  path: string;
  capture_count: number;
  pending: QueueEntry[];
}> {
  const pending = await listPending(paths);
  const packName = `pack_${timestampForFilename()}_${crypto.randomUUID().slice(0, 8)}`;
  const packPath = path.join(paths.packs, packName);
  await mkdir(packPath, { recursive: true });

  await copyIfExists(paths.config, path.join(packPath, "config.json"));
  await copyTree(paths.skills, path.join(packPath, "skills"));
  await copyIfExists(paths.pendingQueue, path.join(packPath, "queue", "pending.jsonl"));

  for (const entry of pending) {
    await copyVaultRelative(paths, entry.raw_capture_path, packPath);
    if (entry.screenshot_path) {
      await copyVaultRelative(paths, entry.screenshot_path, packPath);
    }
  }

  await writeJson(path.join(packPath, "manifest.json"), {
    schema_version: 1,
    created_at: new Date().toISOString(),
    capture_count: pending.length,
    pending,
  });

  return { path: packPath, capture_count: pending.length, pending };
}

async function copyVaultRelative(
  paths: VaultPaths,
  relativePath: string,
  packPath: string,
): Promise<void> {
  await copyIfExists(path.join(paths.root, relativePath), path.join(packPath, relativePath));
}

async function copyIfExists(source: string, destination: string): Promise<void> {
  if (!(await exists(source))) {
    return;
  }

  await mkdir(path.dirname(destination), { recursive: true });
  await copyFile(source, destination);
}

async function copyTree(source: string, destination: string): Promise<void> {
  if (!(await exists(source))) {
    return;
  }

  await mkdir(destination, { recursive: true });
  const entries = await readdir(source, { withFileTypes: true });
  for (const entry of entries) {
    const sourcePath = path.join(source, entry.name);
    const destinationPath = path.join(destination, entry.name);
    if (entry.isDirectory()) {
      await copyTree(sourcePath, destinationPath);
    } else if (entry.isFile()) {
      await copyIfExists(sourcePath, destinationPath);
    }
  }
}

async function isDirectory(filePath: string): Promise<boolean> {
  try {
    return (await stat(filePath)).isDirectory();
  } catch {
    return false;
  }
}

try {
  await program.parseAsync(process.argv);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
