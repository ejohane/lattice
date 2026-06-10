import path from "node:path";
import { AppConfig, VaultPaths } from "../types";
import { loadCapturesForDate, writeJson, writeText } from "../vault";
import { rebuildWikiIndex } from "../index/wiki-index";
import { createLlmProvider } from "../llm/provider";
import { buildSynthesisPrompt, buildSynthesisSystemPrompt } from "./prompt";
import {
  SynthesisResult,
  SynthesisResultSchema,
  validateSynthesisDomain,
} from "./schema";
import { generateValidatedJson } from "./json";
import { renderDailyBrief, renderProposalMarkdown } from "./render";

export interface SynthesisRunResult {
  result: SynthesisResult;
  dailyPath: string;
  proposalMarkdownPath: string;
  proposalJsonPath: string;
  runPath: string;
}

export async function synthesizeDate(input: {
  paths: VaultPaths;
  config: AppConfig;
  date: string;
  providerOverride?: AppConfig["llm"]["provider"];
  modelOverride?: string;
}): Promise<SynthesisRunResult> {
  const captures = await loadCapturesForDate(input.paths, input.date);
  const index = await rebuildWikiIndex(input.paths);
  const providerName = input.providerOverride ?? input.config.llm.provider;
  const provider = createLlmProvider(providerName);
  const model = input.modelOverride ?? input.config.llm.model;
  const generatedAt = new Date().toISOString();
  const system = buildSynthesisSystemPrompt();
  const prompt = buildSynthesisPrompt({
    date: input.date,
    captures,
    pages: index.pages,
    taxonomy: index.taxonomy,
  });

  const generated = await generateValidatedJson({
    provider,
    request: {
      model,
      system,
      prompt,
      temperature: input.config.llm.temperature,
    },
    schema: SynthesisResultSchema,
  });

  const domainErrors = validateSynthesisDomain({
    result: generated.value,
    captures,
    date: input.date,
  });
  if (domainErrors.length > 0) {
    const failedPath = path.join(
      input.paths.synthesisRuns,
      `${input.date}-${Date.now()}-failed.json`,
    );
    await writeJson(failedPath, {
      generated_at: generatedAt,
      provider: providerName,
      model,
      raw_text: generated.rawText,
      errors: domainErrors,
    });
    throw new Error(`Synthesis failed domain validation: ${domainErrors.join(" ")}`);
  }

  const dailyPath = path.join(input.paths.daily, `${input.date}.md`);
  const proposalMarkdownPath = path.join(input.paths.review, `${input.date}.proposal.md`);
  const proposalJsonPath = path.join(input.paths.review, `${input.date}.proposal.json`);
  const runPath = path.join(input.paths.synthesisRuns, `${input.date}-${Date.now()}.json`);

  await writeText(
    dailyPath,
    renderDailyBrief({
      date: input.date,
      result: generated.value,
      captures,
    }),
  );

  await writeText(
    proposalMarkdownPath,
    renderProposalMarkdown({
      date: input.date,
      generatedAt,
      result: generated.value,
      paths: input.paths,
    }),
  );

  await writeJson(proposalJsonPath, {
    date: input.date,
    generated_at: generatedAt,
    proposals: generated.value.wiki_proposals,
  });

  await writeJson(runPath, {
    date: input.date,
    generated_at: generatedAt,
    provider: providerName,
    model,
    repair_attempts: generated.repairAttempts,
    result: generated.value,
    raw_text: generated.rawText,
  });

  return {
    result: generated.value,
    dailyPath,
    proposalMarkdownPath,
    proposalJsonPath,
    runPath,
  };
}
