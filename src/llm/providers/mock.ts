import { CaptureRecord } from "../../types";
import { GenerateTextRequest, GenerateTextResult, LlmProvider } from "../provider";

export class MockProvider implements LlmProvider {
  name = "mock" as const;

  async generateText(request: GenerateTextRequest): Promise<GenerateTextResult> {
    const captures = extractCaptures(request.prompt);
    const pages = extractPageIndex(request.prompt);
    const date = extractDate(request.prompt) ?? captures[0]?.local_date ?? "unknown";
    const firstCaptureIds = captures.slice(0, 3).map((capture) => capture.id);
    const combined = captures.map((capture) => capture.body).join(" ");
    const title = inferTitle(combined);
    const existingPage = pages.find(
      (page) =>
        page.title.toLowerCase() === title.toLowerCase() ||
        page.aliases.some((alias) => alias.toLowerCase() === title.toLowerCase()),
    );

    const result = {
      date,
      daily_summary:
        captures.length === 0
          ? "No captures were available for this date."
          : `Captured ${captures.length} notes. The main thread was ${title.toLowerCase()}.`,
      captured_notes: captures.map((capture) => ({
        capture_id: capture.id,
        time: capture.created_at,
        note: capture.body,
        context_summary: [
          capture.context.active_app,
          capture.context.active_window,
        ]
          .filter(Boolean)
          .join(" - "),
      })),
      themes:
        captures.length === 0
          ? []
          : [
              {
                title,
                summary: `Recurring notes point to ${title.toLowerCase()} as a useful wiki candidate.`,
                source_capture_ids: firstCaptureIds,
              },
            ],
      decisions: findSentences(combined, ["decide", "decision", "use"]).map(
        (text) => ({
          text,
          source_capture_ids: firstCaptureIds,
        }),
      ),
      tasks: findSentences(combined, ["todo", "task", "build", "prototype"]).map(
        (text) => ({
          text,
          source_capture_ids: firstCaptureIds,
        }),
      ),
      open_questions: findSentences(combined, ["?", "question"]).map((text) => ({
        text,
        source_capture_ids: firstCaptureIds,
      })),
      entity_mentions:
        captures.length === 0
          ? []
          : [
              {
                name: title,
                kind: "idea",
                confidence: 0.74,
                rationale: "Mock provider inferred a durable topic from the sample captures.",
                source_capture_ids: firstCaptureIds,
              },
            ],
      wiki_proposals:
        captures.length === 0
          ? []
          : [
              {
                operation: existingPage ? "update_page" : "create_page",
                path: existingPage?.path ?? `Inbox/${title}.md`,
                title,
                reason: existingPage
                  ? "The captures relate to an existing manually created wiki page."
                  : "The captures describe a recurring concept that may deserve a curated page.",
                proposed_markdown: existingPage
                  ? `## Proposed Update\n\nToday reinforced that ${title} should focus on fast capture, manual synthesis, and reviewed wiki updates.\n\nSources: ${firstCaptureIds.join(", ")}`
                  : `# ${title}\n\n## Current Understanding\n\n${title} emerged from today's captures and needs human review before becoming part of the wiki.\n\nSources: ${firstCaptureIds.join(", ")}`,
                source_capture_ids: firstCaptureIds,
              },
            ],
    };

    return {
      text: JSON.stringify(result, null, 2),
      provider: this.name,
      model: request.model,
      usage: {
        input_tokens: Math.ceil(request.prompt.length / 4),
        output_tokens: Math.ceil(JSON.stringify(result).length / 4),
      },
    };
  }
}

function extractDate(prompt: string): string | null {
  return prompt.match(/SYNTHESIS_DATE:\s*(\d{4}-\d{2}-\d{2})/)?.[1] ?? null;
}

function extractCaptures(prompt: string): CaptureRecord[] {
  const match = prompt.match(/BEGIN_CAPTURE_JSON\n([\s\S]*?)\nEND_CAPTURE_JSON/);
  if (!match?.[1]) {
    return [];
  }

  try {
    return JSON.parse(match[1]) as CaptureRecord[];
  } catch {
    return [];
  }
}

function extractPageIndex(prompt: string): Array<{
  title: string;
  path: string;
  aliases: string[];
}> {
  const match = prompt.match(
    /COMPACT_PAGE_INDEX:\n([\s\S]*?)\n\nCOMPACT_TAXONOMY_INDEX:/,
  );
  if (!match?.[1]) {
    return [];
  }

  try {
    const parsed = JSON.parse(match[1]) as Array<{
      title?: string;
      path?: string;
      aliases?: string[];
    }>;
    return parsed
      .filter((page) => page.title && page.path)
      .map((page) => ({
        title: page.title ?? "",
        path: page.path ?? "",
        aliases: page.aliases ?? [],
      }));
  } catch {
    return [];
  }
}

function inferTitle(text: string): string {
  const lower = text.toLowerCase();
  if (lower.includes("context") && lower.includes("note")) {
    return "Lattice";
  }
  if (lower.includes("pricing")) {
    return "Pricing Model";
  }
  if (lower.includes("raycast")) {
    return "Raycast Capture";
  }
  return "Captured Ideas";
}

function findSentences(text: string, needles: string[]): string[] {
  return text
    .split(/(?<=[.!?])\s+/)
    .map((sentence) => sentence.trim())
    .filter((sentence) => {
      const lower = sentence.toLowerCase();
      return needles.some((needle) => lower.includes(needle));
    })
    .slice(0, 5);
}
