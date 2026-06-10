import { CaptureRecord, PageIndexEntry, TaxonomyIndexEntry } from "../types";

export interface PromptInput {
  date: string;
  captures: CaptureRecord[];
  pages: PageIndexEntry[];
  taxonomy: TaxonomyIndexEntry[];
}

export function buildSynthesisSystemPrompt(): string {
  return [
    "You synthesize personal notes into source-grounded daily briefs and proposed wiki updates.",
    "Return only valid JSON. Do not include markdown fences, prose outside JSON, or comments.",
    "Do not invent facts. Every claim in themes, tasks, decisions, questions, entities, and proposals must cite source_capture_ids from the input.",
    "Be conservative about creating wiki pages. Prefer existing pages and categories when the compact index suggests a match.",
    "Use Inbox/ for uncertain page proposals. Do not propose moving, deleting, or reorganizing existing wiki pages.",
    "Daily notes can be log-like. Wiki proposals should be curated and informative, not append logs.",
  ].join("\n");
}

export function buildSynthesisPrompt(input: PromptInput): string {
  const compactCaptures = input.captures.map((capture) => ({
    id: capture.id,
    created_at: capture.created_at,
    local_date: capture.local_date,
    body: capture.body,
    context: {
      active_app: capture.context.active_app,
      active_window: capture.context.active_window,
      screenshot_path: capture.context.screenshot_path,
      metadata_errors: capture.context.metadata_errors,
    },
  }));

  const compactPages = input.pages.map((page) => ({
    title: page.title,
    path: page.path,
    kind: page.kind,
    aliases: page.aliases,
    summary: page.summary,
  }));

  const compactTaxonomy = input.taxonomy.map((entry) => ({
    path: entry.path,
    page_count: entry.page_count,
    description: entry.description,
  }));

  return [
    `SYNTHESIS_DATE: ${input.date}`,
    "",
    "Return JSON with exactly this top-level shape:",
    JSON.stringify(
      {
        date: "YYYY-MM-DD",
        daily_summary: "string",
        captured_notes: [
          {
            capture_id: "string",
            time: "ISO timestamp",
            note: "short note text",
            context_summary: "short context summary",
          },
        ],
        themes: [
          {
            title: "string",
            summary: "string",
            source_capture_ids: ["cap_id"],
          },
        ],
        decisions: [
          {
            text: "string",
            source_capture_ids: ["cap_id"],
          },
        ],
        tasks: [
          {
            text: "string",
            source_capture_ids: ["cap_id"],
          },
        ],
        open_questions: [
          {
            text: "string",
            source_capture_ids: ["cap_id"],
          },
        ],
        entity_mentions: [
          {
            name: "string",
            kind: "person | project | topic | idea | organization | place | other",
            confidence: 0.5,
            rationale: "string",
            source_capture_ids: ["cap_id"],
          },
        ],
        wiki_proposals: [
          {
            operation: "create_category | create_page | update_page",
            path: "relative path under wiki, Markdown pages end in .md",
            title: "string",
            reason: "string",
            proposed_markdown: "complete proposed page content or replacement section",
            source_capture_ids: ["cap_id"],
          },
        ],
      },
      null,
      2,
    ),
    "",
    "Rules:",
    "- Use empty arrays when nothing is supported by the captures.",
    "- Keep daily_summary under 180 words.",
    "- Keep each proposed wiki page/update concise and useful.",
    "- Reuse existing page paths when the page index suggests a match.",
    "- Use create_category only when a folder would clearly improve organization.",
    "- Do not include screenshots in the analysis beyond referencing screenshot_path when useful.",
    "",
    "COMPACT_PAGE_INDEX:",
    JSON.stringify(compactPages, null, 2),
    "",
    "COMPACT_TAXONOMY_INDEX:",
    JSON.stringify(compactTaxonomy, null, 2),
    "",
    "BEGIN_CAPTURE_JSON",
    JSON.stringify(compactCaptures, null, 2),
    "END_CAPTURE_JSON",
  ].join("\n");
}
