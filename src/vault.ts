import path from "node:path";
import { mkdir, readFile, readdir, stat, writeFile, appendFile } from "node:fs/promises";
import {
  AppConfig,
  CaptureRecord,
  CaptureRecordSchema,
  DEFAULT_CONFIG,
  VaultPaths,
} from "./types";
import { mergeConfig } from "./config";

export function getVaultPaths(root: string): VaultPaths {
  return {
    root,
    raw: path.join(root, "raw"),
    captures: path.join(root, "captures"),
    screenshots: path.join(root, "screenshots"),
    daily: path.join(root, "daily"),
    wiki: path.join(root, "wiki"),
    index: path.join(root, "index"),
    review: path.join(root, "review"),
    synthesis: path.join(root, "synthesis"),
    synthesisRuns: path.join(root, "synthesis", "runs"),
    config: path.join(root, "config.json"),
  };
}

export async function ensureVault(root: string): Promise<VaultPaths> {
  const paths = getVaultPaths(root);
  await Promise.all([
    mkdir(paths.raw, { recursive: true }),
    mkdir(paths.captures, { recursive: true }),
    mkdir(paths.screenshots, { recursive: true }),
    mkdir(paths.daily, { recursive: true }),
    mkdir(path.join(paths.wiki, "Inbox"), { recursive: true }),
    mkdir(paths.index, { recursive: true }),
    mkdir(paths.review, { recursive: true }),
    mkdir(paths.synthesisRuns, { recursive: true }),
  ]);

  if (!(await exists(paths.config))) {
    await writeJson(paths.config, DEFAULT_CONFIG);
  }

  return paths;
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
): Promise<void> {
  const parsed = CaptureRecordSchema.parse(capture);
  const captureDir = path.join(paths.captures, parsed.local_date);
  await mkdir(captureDir, { recursive: true });
  await writeJson(path.join(captureDir, `${parsed.id}.json`), parsed);
  await appendFile(
    path.join(paths.raw, `${parsed.local_date}.jsonl`),
    `${JSON.stringify(parsed)}\n`,
    "utf8",
  );
}

export async function loadCapturesForDate(
  paths: VaultPaths,
  date: string,
): Promise<CaptureRecord[]> {
  const rawFile = path.join(paths.raw, `${date}.jsonl`);
  if (!(await exists(rawFile))) {
    return [];
  }

  const lines = (await readFile(rawFile, "utf8"))
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  return lines.map((line) => CaptureRecordSchema.parse(JSON.parse(line)));
}

export async function writeJson(filePath: string, value: unknown): Promise<void> {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

export async function writeText(filePath: string, value: string): Promise<void> {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, value.endsWith("\n") ? value : `${value}\n`, "utf8");
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
