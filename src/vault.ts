import path from "node:path";
import { appendFile, mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import {
  AppConfig,
  CaptureRecord,
  CaptureRecordSchema,
  DEFAULT_CONFIG,
  QueueEntry,
  VaultPaths,
} from "./types";
import { mergeConfig } from "./config";
import { bundledSkillTemplates } from "./skill-templates";

export function getVaultPaths(root: string): VaultPaths {
  const raw = path.join(root, "raw");
  const queue = path.join(root, "queue");
  const wiki = path.join(root, "wiki");
  const skills = path.join(root, "skills");
  const exportsDir = path.join(root, "exports");
  const synthesis = path.join(root, "synthesis");

  return {
    root,
    raw,
    rawLog: path.join(raw, "log.jsonl"),
    captures: path.join(raw, "captures"),
    screenshots: path.join(raw, "screenshots"),
    queue,
    pendingQueue: path.join(queue, "pending.jsonl"),
    ingestedQueue: path.join(queue, "ingested.jsonl"),
    daily: path.join(root, "daily"),
    wiki,
    wikiPages: path.join(wiki, "pages"),
    skills,
    exports: exportsDir,
    packs: path.join(exportsDir, "packs"),
    index: path.join(root, "index"),
    review: path.join(root, "review"),
    synthesis,
    synthesisRuns: path.join(synthesis, "runs"),
    config: path.join(root, "config.json"),
  };
}

export async function ensureVault(
  root: string,
  options: { installSkills?: boolean } = {},
): Promise<VaultPaths> {
  const paths = getVaultPaths(root);
  await Promise.all([
    mkdir(paths.raw, { recursive: true }),
    mkdir(paths.captures, { recursive: true }),
    mkdir(paths.screenshots, { recursive: true }),
    mkdir(paths.queue, { recursive: true }),
    mkdir(paths.wikiPages, { recursive: true }),
    mkdir(paths.skills, { recursive: true }),
    mkdir(paths.packs, { recursive: true }),
  ]);

  if (!(await exists(paths.config))) {
    await writeJson(paths.config, DEFAULT_CONFIG);
  }

  await writeStarterFile(
    path.join(paths.wiki, "index.md"),
    [
      "# Lattice Wiki",
      "",
      "This wiki is owned by your maintenance agents. Use `wiki/pages/` for durable pages and `wiki/log.md` for the running maintenance log.",
    ].join("\n"),
  );
  await writeStarterFile(
    path.join(paths.wiki, "log.md"),
    [
      "# Wiki Maintenance Log",
      "",
      "Agents should append dated notes here when they ingest captures or reorganize pages.",
    ].join("\n"),
  );
  if (options.installSkills !== false) {
    await installBundledSkills(paths);
  }

  return paths;
}

export async function installBundledSkills(
  paths: VaultPaths,
  options: { overwrite?: boolean } = {},
): Promise<{
  installed: string[];
  skipped: string[];
}> {
  await mkdir(paths.skills, { recursive: true });
  const installed: string[] = [];
  const skipped: string[] = [];

  for (const template of bundledSkillTemplates) {
    const relativePath = template.relativePath;
    const destinationPath = path.join(paths.skills, relativePath);
    const vaultRelativePath = path.relative(paths.root, destinationPath);
    if (!options.overwrite && await exists(destinationPath)) {
      skipped.push(vaultRelativePath);
      continue;
    }

    await writeText(destinationPath, template.content);
    installed.push(vaultRelativePath);
  }

  return { installed, skipped };
}

export async function loadConfig(root: string): Promise<AppConfig> {
  const paths = await ensureVault(root);
  if (!(await exists(paths.config))) {
    return DEFAULT_CONFIG;
  }

  try {
    return mergeConfig(JSON.parse(await readFile(paths.config, "utf8")));
  } catch {
    return DEFAULT_CONFIG;
  }
}

export async function saveCapture(
  paths: VaultPaths,
  capture: CaptureRecord,
): Promise<QueueEntry> {
  const parsed = CaptureRecordSchema.parse(capture);
  const captureDir = path.join(paths.captures, parsed.local_date);
  await mkdir(captureDir, { recursive: true });
  const capturePath = path.join(captureDir, `${parsed.id}.json`);
  if (await exists(capturePath)) {
    throw new Error(`Raw capture already exists: ${path.relative(paths.root, capturePath)}`);
  }

  await writeJson(capturePath, parsed);
  await appendJsonLine(paths.rawLog, parsed);

  return {
    schema_version: 1,
    capture_id: parsed.id,
    created_at: parsed.created_at,
    local_date: parsed.local_date,
    source: parsed.source,
    raw_capture_path: path.relative(paths.root, capturePath),
    screenshot_path: parsed.context.screenshot_path,
  };
}

export async function loadCapturesForDate(
  paths: VaultPaths,
  date: string,
): Promise<CaptureRecord[]> {
  const captureDir = path.join(paths.captures, date);
  if (!(await exists(captureDir))) {
    return [];
  }

  const entries = (await readdir(captureDir, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => entry.name)
    .sort();

  return Promise.all(
    entries.map(async (entry) =>
      CaptureRecordSchema.parse(JSON.parse(await readFile(path.join(captureDir, entry), "utf8"))),
    ),
  );
}

export async function writeJson(filePath: string, value: unknown): Promise<void> {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export async function writeText(filePath: string, value: string): Promise<void> {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, value.endsWith("\n") ? value : `${value}\n`, "utf8");
}

export async function appendJsonLine(filePath: string, value: unknown): Promise<void> {
  await mkdir(path.dirname(filePath), { recursive: true });
  await appendFile(filePath, `${JSON.stringify(value)}\n`, "utf8");
}

export async function readJsonIfExists(filePath: string): Promise<unknown | null> {
  if (!(await exists(filePath))) {
    return null;
  }

  return JSON.parse(await readFile(filePath, "utf8"));
}

export async function exists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

export async function listMarkdownFiles(root: string): Promise<string[]> {
  if (!(await exists(root))) {
    return [];
  }

  const out: string[] = [];
  await walk(root, out);
  return out.filter((file) => file.endsWith(".md"));
}

async function walk(current: string, out: string[]): Promise<void> {
  const entries = await readdir(current, { withFileTypes: true });
  for (const entry of entries) {
    const entryPath = path.join(current, entry.name);
    if (entry.isDirectory()) {
      await walk(entryPath, out);
    } else if (entry.isFile()) {
      out.push(entryPath);
    }
  }
}

async function writeStarterFile(filePath: string, value: string): Promise<void> {
  if (await exists(filePath)) {
    return;
  }

  await writeText(filePath, value);
}
