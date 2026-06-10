#!/usr/bin/env bun
import { Command } from "commander";
import path from "node:path";
import { resolveVaultPath } from "./config";
import { createCapture } from "./capture/capture";
import { rebuildWikiIndex } from "./index/wiki-index";
import { createLlmProvider } from "./llm/provider";
import { toLocalDateString } from "./time";
import { DEFAULT_CONFIG, ProviderNameSchema } from "./types";
import { ensureVault, exists, getVaultPaths, loadConfig, writeText } from "./vault";
import { synthesizeDate } from "./synthesis/synthesize";

const program = new Command();

program
  .name("lattice")
  .description("Minimal local-first capture and synthesis system.")
  .option("--vault <path>", "Vault path. Defaults to LATTICE_VAULT_PATH or ./LatticeVault.");

program
  .command("init")
  .description("Create the vault folder structure.")
  .action(async () => {
    const root = resolveVaultPath(program.opts().vault);
    await ensureVault(root);
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
  .command("synthesize")
  .description("Manually synthesize captures for a date.")
  .option("--date <yyyy-mm-dd>", "Date to synthesize.", toLocalDateString(new Date()))
  .option("--provider <provider>", "Override provider: copilot, opencode, openai, or mock.")
  .option("--harness <harness>", "Alias for --provider.")
  .option("--model <model>", "Override model.")
  .option("--json", "Print machine-readable JSON.")
  .action(async (options) => {
    const root = resolveVaultPath(program.opts().vault);
    const paths = await ensureVault(root);
    const config = await loadConfig(root);
    const providerOption = options.harness ?? options.provider;
    const providerOverride = providerOption
      ? ProviderNameSchema.parse(providerOption)
      : undefined;

    const synthesizeInput: Parameters<typeof synthesizeDate>[0] = {
      paths,
      config,
      date: options.date,
    };
    if (providerOverride) {
      synthesizeInput.providerOverride = providerOverride;
    }
    if (options.model) {
      synthesizeInput.modelOverride = options.model;
    }

    const result = await synthesizeDate(synthesizeInput);

    if (options.json) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`Daily brief: ${path.relative(root, result.dailyPath)}`);
      console.log(`Wiki proposal: ${path.relative(root, result.proposalMarkdownPath)}`);
      console.log(`Run artifact: ${path.relative(root, result.runPath)}`);
    }
  });

program
  .command("index")
  .description("Rebuild compact wiki indexes.")
  .option("--json", "Print machine-readable JSON.")
  .action(async (options) => {
    const root = resolveVaultPath(program.opts().vault);
    const paths = await ensureVault(root);
    const index = await rebuildWikiIndex(paths);
    if (options.json) {
      console.log(JSON.stringify(index, null, 2));
    } else {
      console.log(`Indexed ${index.pages.length} wiki pages.`);
    }
  });

program
  .command("provider-check")
  .description("Run a minimal provider compatibility check.")
  .option("--provider <provider>", "Provider to check.", "mock")
  .option("--harness <harness>", "Alias for --provider.")
  .option("--model <model>", "Model to request.")
  .action(async (options) => {
    const root = resolveVaultPath(program.opts().vault);
    const config = (await exists(getVaultPaths(root).config))
      ? await loadConfig(root)
      : DEFAULT_CONFIG;
    const providerName = ProviderNameSchema.parse(options.harness ?? options.provider);
    const provider = createLlmProvider(providerName);
    const response = await provider.generateText({
      model: options.model ?? config.llm.model,
      system: "Return only JSON.",
      prompt: 'Return {"ok": true}.',
      temperature: 0,
    });
    console.log(response.text);
  });

program
  .command("verify")
  .description("Run a token-free end-to-end verification with the mock provider.")
  .action(async () => {
    const root = path.join(process.cwd(), "work", `verify-vault-${Date.now()}`);
    const paths = await ensureVault(root);
    const first = await createCapture({
      paths,
      body: "Build the lattice with Raycast capture and manual synthesis.",
      source: "verify",
      screenshot: false,
      now: new Date("2026-06-09T15:00:00-05:00"),
    });
    await createCapture({
      paths,
      body: "Decision: use proposed wiki updates for review instead of automatic wiki edits.",
      source: "verify",
      screenshot: false,
      now: new Date("2026-06-09T15:05:00-05:00"),
    });
    await writeText(
      path.join(paths.wiki, "Inbox", "Lattice.md"),
      [
        "---",
        "title: Lattice",
        "kind: project",
        "summary: A Raycast-first local capture and synthesis app.",
        "aliases:",
        "  - lattice capture",
        "---",
        "",
        "# Lattice",
        "",
        "A manually created wiki page used by the verification flow.",
      ].join("\n"),
    );
    const config = await loadConfig(root);
    const result = await synthesizeDate({
      paths,
      config,
      date: first.local_date,
      providerOverride: "mock",
    });
    console.log(`Verified capture and synthesis in ${root}`);
    console.log(`Daily brief: ${result.dailyPath}`);
    console.log(`Proposal: ${result.proposalMarkdownPath}`);
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

try {
  await program.parseAsync(process.argv);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
