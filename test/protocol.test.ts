import { describe, expect, test } from "bun:test";
import os from "node:os";
import path from "node:path";
import { mkdir, readFile } from "node:fs/promises";
import { createCapture } from "../src/capture/capture";
import { listIngested, listPending, markIngested } from "../src/queue";
import {
  ensureVault,
  exists,
  installBundledSkills,
  loadCapturesForDate,
  writeText,
} from "../src/vault";

describe("vault protocol", () => {
  test("initializes the durable vault layout", async () => {
    const root = await tempRoot();
    const paths = await ensureVault(root);

    expect(await exists(path.join(paths.raw, "captures"))).toBe(true);
    expect(await exists(path.join(paths.raw, "screenshots"))).toBe(true);
    expect(await exists(paths.queue)).toBe(true);
    expect(await exists(path.join(paths.wiki, "index.md"))).toBe(true);
    expect(await exists(path.join(paths.wiki, "log.md"))).toBe(true);
    expect(await exists(paths.wikiPages)).toBe(true);
    expect(await exists(path.join(paths.skills, "AGENTS.md"))).toBe(true);
    expect(await exists(path.join(paths.skills, "ingest-captures.md"))).toBe(true);
    expect(await exists(path.join(paths.skills, "maintain-wiki.md"))).toBe(true);
    expect(await exists(path.join(paths.skills, "answer-from-wiki.md"))).toBe(true);
    expect(await exists(path.join(paths.skills, "lint-wiki.md"))).toBe(true);
    expect(await exists(paths.packs)).toBe(true);
    expect(await exists(paths.config)).toBe(true);
  });

  test("installs bundled skills without overwriting local edits unless forced", async () => {
    const root = await tempRoot();
    const paths = await ensureVault(root, { installSkills: false });
    const agentsPath = path.join(paths.skills, "AGENTS.md");

    const firstInstall = await installBundledSkills(paths);
    expect(firstInstall.installed).toContain("skills/AGENTS.md");
    expect(firstInstall.skipped).toEqual([]);

    await writeText(agentsPath, "# Local skill guide");
    const secondInstall = await installBundledSkills(paths);
    expect(secondInstall.installed).not.toContain("skills/AGENTS.md");
    expect(secondInstall.skipped).toContain("skills/AGENTS.md");
    expect(await readFile(agentsPath, "utf8")).toBe("# Local skill guide\n");

    const forcedInstall = await installBundledSkills(paths, { overwrite: true });
    expect(forcedInstall.installed).toContain("skills/AGENTS.md");
    expect(await readFile(agentsPath, "utf8")).toContain("# Lattice Vault Agent Guide");
  });

  test("writes immutable raw captures and pending queue entries", async () => {
    const root = await tempRoot();
    const paths = await ensureVault(root);
    const capture = await createCapture({
      paths,
      body: "Build Lattice around raw context capture.",
      source: "test",
      screenshot: false,
      now: new Date("2026-06-09T10:00:00-05:00"),
    });

    expect(capture.schema_version).toBe(1);
    expect(capture.kind).toBe("capture");
    expect(capture.local_date).toBe("2026-06-09");
    expect(capture.context.screenshot_path).toBeNull();
    expect(Array.isArray(capture.context.metadata_errors)).toBe(true);

    const rawPath = path.join(paths.captures, "2026-06-09", `${capture.id}.json`);
    expect(await exists(rawPath)).toBe(true);
    expect(await exists(paths.rawLog)).toBe(true);

    const loaded = await loadCapturesForDate(paths, "2026-06-09");
    expect(loaded).toHaveLength(1);
    expect(loaded[0]?.id).toBe(capture.id);

    const pending = await listPending(paths);
    expect(pending).toEqual([
      {
        schema_version: 1,
        capture_id: capture.id,
        created_at: capture.created_at,
        local_date: "2026-06-09",
        source: "test",
        raw_capture_path: path.relative(root, rawPath),
        screenshot_path: null,
      },
    ]);

    const rawLog = await readFile(paths.rawLog, "utf8");
    expect(rawLog).toContain(capture.id);
  });

  test("marks pending captures ingested without changing raw files", async () => {
    const root = await tempRoot();
    const paths = await ensureVault(root);
    const capture = await createCapture({
      paths,
      body: "Decision: external agents maintain the wiki.",
      source: "test",
      screenshot: false,
      now: new Date("2026-06-09T10:05:00-05:00"),
    });
    const rawPath = path.join(paths.captures, capture.local_date, `${capture.id}.json`);
    const rawBefore = await readFile(rawPath, "utf8");

    const result = await markIngested({
      paths,
      captureIds: [capture.id],
      agent: "test-agent",
      now: new Date("2026-06-09T11:00:00-05:00"),
    });

    expect(result.missing).toEqual([]);
    expect(result.ingested).toHaveLength(1);
    expect(result.ingested[0]?.agent).toBe("test-agent");
    expect(await listPending(paths)).toEqual([]);
    expect(await listIngested(paths)).toHaveLength(1);
    expect(await readFile(rawPath, "utf8")).toBe(rawBefore);
  });

  test("does not partially ingest when a requested capture is missing", async () => {
    const root = await tempRoot();
    const paths = await ensureVault(root);
    const capture = await createCapture({
      paths,
      body: "Keep queue operations explicit.",
      source: "test",
      screenshot: false,
      now: new Date("2026-06-09T10:10:00-05:00"),
    });

    const result = await markIngested({
      paths,
      captureIds: [capture.id, "cap_missing"],
      agent: "test-agent",
    });

    expect(result.ingested).toEqual([]);
    expect(result.missing).toEqual(["cap_missing"]);
    expect(await listPending(paths)).toHaveLength(1);
    expect(await listIngested(paths)).toEqual([]);
  });
});

async function tempRoot(): Promise<string> {
  const root = path.join(os.tmpdir(), `lattice-test-${crypto.randomUUID()}`);
  await mkdir(root, { recursive: true });
  return root;
}
