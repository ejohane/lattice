import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  IngestedEntry,
  IngestedEntrySchema,
  QueueEntry,
  QueueEntrySchema,
  VaultPaths,
} from "./types";
import { appendJsonLine, exists } from "./vault";

export async function enqueueCapture(
  paths: VaultPaths,
  entry: QueueEntry,
): Promise<void> {
  const parsed = QueueEntrySchema.parse(entry);
  await appendJsonLine(paths.pendingQueue, parsed);
}

export async function listPending(paths: VaultPaths): Promise<QueueEntry[]> {
  return readJsonl(paths.pendingQueue, (value) => QueueEntrySchema.parse(value));
}

export async function listIngested(paths: VaultPaths): Promise<IngestedEntry[]> {
  return readJsonl(paths.ingestedQueue, (value) => IngestedEntrySchema.parse(value));
}

export async function markIngested(input: {
  paths: VaultPaths;
  captureIds: string[];
  agent: string;
  now?: Date;
}): Promise<{
  ingested: IngestedEntry[];
  missing: string[];
}> {
  const pending = await listPending(input.paths);
  const requested = new Set(input.captureIds);
  const kept: QueueEntry[] = [];
  const matched: QueueEntry[] = [];

  for (const entry of pending) {
    if (requested.has(entry.capture_id)) {
      matched.push(entry);
    } else {
      kept.push(entry);
    }
  }

  const matchedIds = new Set(matched.map((entry) => entry.capture_id));
  const missing = input.captureIds.filter((id) => !matchedIds.has(id));
  if (missing.length > 0) {
    return { ingested: [], missing };
  }

  const ingestedAt = (input.now ?? new Date()).toISOString();
  const ingested = matched.map((entry) =>
    IngestedEntrySchema.parse({
      ...entry,
      ingested_at: ingestedAt,
      agent: input.agent,
    }),
  );

  await writeJsonl(input.paths.pendingQueue, kept);
  for (const entry of ingested) {
    await appendJsonLine(input.paths.ingestedQueue, entry);
  }

  return { ingested, missing: [] };
}

async function readJsonl<T>(
  filePath: string,
  parse: (value: unknown) => T,
): Promise<T[]> {
  if (!(await exists(filePath))) {
    return [];
  }

  const lines = (await readFile(filePath, "utf8"))
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  return lines.map((line) => parse(JSON.parse(line)));
}

async function writeJsonl(filePath: string, values: unknown[]): Promise<void> {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(
    filePath,
    values.length > 0 ? `${values.map((value) => JSON.stringify(value)).join("\n")}\n` : "",
    "utf8",
  );
}
