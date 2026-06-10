import path from "node:path";
import { z } from "zod";
import { CaptureRecord } from "../types";

const SourceBackedSchema = z.object({
  text: z.string().min(1),
  source_capture_ids: z.array(z.string()).min(1),
});

export const WikiProposalSchema = z.object({
  operation: z.enum(["create_category", "create_page", "update_page"]),
  path: z.string().min(1),
  title: z.string().min(1),
  reason: z.string().min(1),
  proposed_markdown: z.string().min(1),
  source_capture_ids: z.array(z.string()).min(1),
});

export const SynthesisResultSchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  daily_summary: z.string().min(1),
  captured_notes: z.array(
    z.object({
      capture_id: z.string(),
      time: z.string(),
      note: z.string(),
      context_summary: z.string(),
    }),
  ),
  themes: z.array(
    z.object({
      title: z.string().min(1),
      summary: z.string().min(1),
      source_capture_ids: z.array(z.string()).min(1),
    }),
  ),
  decisions: z.array(SourceBackedSchema),
  tasks: z.array(SourceBackedSchema),
  open_questions: z.array(SourceBackedSchema),
  entity_mentions: z.array(
    z.object({
      name: z.string().min(1),
      kind: z.string().min(1),
      confidence: z.number().min(0).max(1),
      rationale: z.string().min(1),
      source_capture_ids: z.array(z.string()).min(1),
    }),
  ),
  wiki_proposals: z.array(WikiProposalSchema),
});

export type SynthesisResult = z.infer<typeof SynthesisResultSchema>;
export type WikiProposal = z.infer<typeof WikiProposalSchema>;

export function validateSynthesisDomain(input: {
  result: SynthesisResult;
  captures: CaptureRecord[];
  date: string;
}): string[] {
  const errors: string[] = [];
  const ids = new Set(input.captures.map((capture) => capture.id));

  if (input.result.date !== input.date) {
    errors.push(`Expected date ${input.date}, got ${input.result.date}.`);
  }

  const sourceLists: string[][] = [
    ...input.result.themes.map((theme) => theme.source_capture_ids),
    ...input.result.decisions.map((decision) => decision.source_capture_ids),
    ...input.result.tasks.map((task) => task.source_capture_ids),
    ...input.result.open_questions.map((question) => question.source_capture_ids),
    ...input.result.entity_mentions.map((entity) => entity.source_capture_ids),
    ...input.result.wiki_proposals.map((proposal) => proposal.source_capture_ids),
  ];

  for (const sourceList of sourceLists) {
    for (const id of sourceList) {
      if (!ids.has(id)) {
        errors.push(`Unknown source_capture_id: ${id}.`);
      }
    }
  }

  for (const proposal of input.result.wiki_proposals) {
    errors.push(...validateProposalPath(proposal.operation, proposal.path));
  }

  return errors;
}

function validateProposalPath(operation: WikiProposal["operation"], value: string): string[] {
  const errors: string[] = [];
  if (path.isAbsolute(value)) {
    errors.push(`Wiki proposal path must be relative: ${value}.`);
  }

  const normalized = path.normalize(value);
  if (normalized.startsWith("..") || normalized.includes(`${path.sep}..${path.sep}`)) {
    errors.push(`Wiki proposal path cannot leave the wiki root: ${value}.`);
  }

  if (operation === "create_page" || operation === "update_page") {
    if (!value.endsWith(".md")) {
      errors.push(`Wiki page proposal must target a Markdown file: ${value}.`);
    }
  }

  if (operation === "create_category" && value.endsWith(".md")) {
    errors.push(`Category proposal must target a folder path, not a Markdown file: ${value}.`);
  }

  return errors;
}
