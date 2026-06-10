import { describe, expect, test } from "bun:test";
import os from "node:os";
import path from "node:path";
import { mkdir } from "node:fs/promises";
import { createCapture } from "../src/capture/capture";
import { rebuildWikiIndex } from "../src/index/wiki-index";
import { synthesizeDate } from "../src/synthesis/synthesize";
import { validateSynthesisDomain } from "../src/synthesis/schema";
import { DEFAULT_CONFIG } from "../src/types";
import { ensureVault, exists, loadCapturesForDate, writeText } from "../src/vault";

describe("synthesis flow", () => {
  test("indexes manual wiki pages", async () => {
    const root = await tempRoot();
    const paths = await ensureVault(root);
    await writeText(
      path.join(paths.wiki, "Product Ideas", "Lattice.md"),
      [
        "---",
        "title: Lattice",
        "kind: project",
        "summary: Local capture app.",
        "aliases:",
        "  - context capture",
        "---",
        "",
        "# Lattice",
      ].join("\n"),
    );

    const index = await rebuildWikiIndex(paths);
    expect(index.pages).toHaveLength(1);
    expect(index.pages[0]?.title).toBe("Lattice");
    expect(index.aliases["context capture"]).toBe(
      "Product Ideas/Lattice.md",
    );
  });

  test("runs token-free synthesis and writes review artifacts", async () => {
    const root = await tempRoot();
    const paths = await ensureVault(root);
    const first = await createCapture({
      paths,
      body: "Build the lattice with fast capture.",
      source: "test",
      screenshot: false,
      now: new Date("2026-06-09T10:00:00-05:00"),
    });
    await createCapture({
      paths,
      body: "Decision: use proposed wiki updates for review.",
      source: "test",
      screenshot: false,
      now: new Date("2026-06-09T10:05:00-05:00"),
    });

    const captures = await loadCapturesForDate(paths, first.local_date);
    expect(captures).toHaveLength(2);

    const run = await synthesizeDate({
      paths,
      config: {
        ...DEFAULT_CONFIG,
        llm: {
          ...DEFAULT_CONFIG.llm,
          provider: "mock",
        },
      },
      date: first.local_date,
      providerOverride: "mock",
    });

    expect(run.result.date).toBe("2026-06-09");
    expect(await exists(run.dailyPath)).toBe(true);
    expect(await exists(run.proposalMarkdownPath)).toBe(true);
    expect(await exists(run.proposalJsonPath)).toBe(true);
    expect(await exists(run.runPath)).toBe(true);
  });

  test("rejects unknown source ids", () => {
    const errors = validateSynthesisDomain({
      captures: [
        {
          id: "cap_real",
          created_at: "2026-06-09T15:00:00.000Z",
          local_date: "2026-06-09",
          body: "hello",
          source: "test",
          context: {
            active_app: null,
            active_window: null,
            screenshot_path: null,
            metadata_errors: [],
          },
        },
      ],
      date: "2026-06-09",
      result: {
        date: "2026-06-09",
        daily_summary: "Summary",
        captured_notes: [],
        themes: [
          {
            title: "Bad",
            summary: "Bad",
            source_capture_ids: ["cap_missing"],
          },
        ],
        decisions: [],
        tasks: [],
        open_questions: [],
        entity_mentions: [],
        wiki_proposals: [],
      },
    });

    expect(errors.join(" ")).toContain("cap_missing");
  });
});

async function tempRoot(): Promise<string> {
  const root = path.join(
    os.tmpdir(),
    `lattice-test-${crypto.randomUUID()}`,
  );
  await mkdir(root, { recursive: true });
  return root;
}
