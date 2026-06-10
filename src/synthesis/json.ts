import { z } from "zod";
import { GenerateTextRequest, LlmProvider } from "../llm/provider";

export function parseJsonFromText(text: string): unknown {
  const trimmed = stripCodeFence(text.trim());
  try {
    return JSON.parse(trimmed);
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start === -1 || end === -1 || end <= start) {
      throw new Error("Model response did not contain a JSON object.");
    }

    return JSON.parse(trimmed.slice(start, end + 1));
  }
}

export async function generateValidatedJson<T>(input: {
  provider: LlmProvider;
  request: GenerateTextRequest;
  schema: z.ZodType<T>;
  maxRepairAttempts?: number;
}): Promise<{ value: T; rawText: string; repairAttempts: number }> {
  const maxRepairAttempts = input.maxRepairAttempts ?? 2;
  let rawText = (await input.provider.generateText(input.request)).text;
  let lastError: unknown = null;

  for (let attempt = 0; attempt <= maxRepairAttempts; attempt += 1) {
    try {
      const parsed = parseJsonFromText(rawText);
      return {
        value: input.schema.parse(parsed),
        rawText,
        repairAttempts: attempt,
      };
    } catch (error) {
      lastError = error;
      if (attempt === maxRepairAttempts) {
        break;
      }

      rawText = (
        await input.provider.generateText({
          ...input.request,
          prompt: buildRepairPrompt(rawText, error),
        })
      ).text;
    }
  }

  throw new Error(`Could not parse valid synthesis JSON: ${String(lastError)}`);
}

function stripCodeFence(text: string): string {
  const match = text.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  return match?.[1] ?? text;
}

function buildRepairPrompt(rawText: string, error: unknown): string {
  return [
    "The previous response was invalid JSON or did not match the required schema.",
    "Return only corrected JSON. Do not include markdown fences or explanation.",
    `Validation/parsing error: ${String(error)}`,
    "",
    "Previous response:",
    rawText,
  ].join("\n");
}
