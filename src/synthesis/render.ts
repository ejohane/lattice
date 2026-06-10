import path from "node:path";
import { CaptureRecord, VaultPaths } from "../types";
import { toLocalTimeString } from "../time";
import { SynthesisResult } from "./schema";

export function renderDailyBrief(input: {
  date: string;
  result: SynthesisResult;
  captures: CaptureRecord[];
}): string {
  const captureById = new Map(input.captures.map((capture) => [capture.id, capture]));

  return [
    `# Daily Brief: ${input.date}`,
    "",
    "## Summary",
    "",
    input.result.daily_summary,
    "",
    "## Notes Captured",
    "",
    ...input.captures.flatMap((capture) => {
      const createdAt = new Date(capture.created_at);
      const parts = [
        `- ${toLocalTimeString(createdAt)} - ${capture.body.replace(/\s+/g, " ").trim()} \`${capture.id}\``,
      ];
      if (capture.context.active_app || capture.context.active_window) {
        parts.push(
          `  Context: ${[capture.context.active_app, capture.context.active_window]
            .filter(Boolean)
            .join(" - ")}`,
        );
      }
      if (capture.context.screenshot_path) {
        parts.push(`  Screenshot: ${capture.context.screenshot_path}`);
      }
      if (capture.context.metadata_errors.length > 0) {
        parts.push(`  Metadata errors: ${capture.context.metadata_errors.join("; ")}`);
      }
      return parts;
    }),
    "",
    "## Themes",
    "",
    ...renderThemes(input.result.themes),
    "",
    "## Decisions",
    "",
    ...renderSourceBacked(input.result.decisions),
    "",
    "## Tasks",
    "",
    ...renderSourceBacked(input.result.tasks),
    "",
    "## Open Questions",
    "",
    ...renderSourceBacked(input.result.open_questions),
    "",
    "## Entity Mentions",
    "",
    ...renderEntities(input.result.entity_mentions),
    "",
    "## Wiki Proposals",
    "",
    ...(input.result.wiki_proposals.length === 0
      ? ["- None"]
      : input.result.wiki_proposals.map(
          (proposal) =>
            `- ${proposal.operation}: ${proposal.path} - ${proposal.reason} (${formatSources(
              proposal.source_capture_ids,
              captureById,
            )})`,
        )),
  ].join("\n");
}

export function renderProposalMarkdown(input: {
  date: string;
  generatedAt: string;
  result: SynthesisResult;
  paths: VaultPaths;
}): string {
  return [
    `# Wiki Update Proposals: ${input.date}`,
    "",
    `Generated: ${input.generatedAt}`,
    "",
    "These are proposed changes only. No wiki files were changed automatically.",
    "",
    ...input.result.wiki_proposals.flatMap((proposal, index) => [
      `## ${index + 1}. ${proposal.operation}: ${proposal.title}`,
      "",
      `Path: ${path.join("wiki", proposal.path)}`,
      "",
      `Reason: ${proposal.reason}`,
      "",
      `Sources: ${proposal.source_capture_ids.map((id) => `\`${id}\``).join(", ")}`,
      "",
      "```markdown",
      proposal.proposed_markdown.trim(),
      "```",
      "",
    ]),
  ].join("\n");
}

function renderThemes(themes: SynthesisResult["themes"]): string[] {
  if (themes.length === 0) {
    return ["- None"];
  }

  return themes.map(
    (theme) =>
      `- ${theme.title}: ${theme.summary} (${theme.source_capture_ids
        .map((id) => `\`${id}\``)
        .join(", ")})`,
  );
}

function renderSourceBacked(
  items: Array<{ text: string; source_capture_ids: string[] }>,
): string[] {
  if (items.length === 0) {
    return ["- None"];
  }

  return items.map(
    (item) =>
      `- ${item.text} (${item.source_capture_ids.map((id) => `\`${id}\``).join(", ")})`,
  );
}

function renderEntities(entities: SynthesisResult["entity_mentions"]): string[] {
  if (entities.length === 0) {
    return ["- None"];
  }

  return entities.map(
    (entity) =>
      `- ${entity.name} (${entity.kind}, confidence ${entity.confidence}): ${
        entity.rationale
      } (${entity.source_capture_ids.map((id) => `\`${id}\``).join(", ")})`,
  );
}

function formatSources(
  sourceIds: string[],
  captureById: Map<string, CaptureRecord>,
): string {
  return sourceIds
    .map((id) => (captureById.has(id) ? `\`${id}\`` : `unknown:${id}`))
    .join(", ");
}
