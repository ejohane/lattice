import { describe, expect, test } from "bun:test";
import { z } from "zod";
import { parseJsonFromText, generateValidatedJson } from "../src/synthesis/json";
import { LlmProvider } from "../src/llm/provider";

describe("parseJsonFromText", () => {
  test("parses plain JSON", () => {
    expect(parseJsonFromText('{"ok":true}')).toEqual({ ok: true });
  });

  test("parses fenced JSON", () => {
    expect(parseJsonFromText('```json\n{"ok":true}\n```')).toEqual({ ok: true });
  });

  test("extracts JSON object from extra text", () => {
    expect(parseJsonFromText('Here:\n{"ok":true}\nDone')).toEqual({ ok: true });
  });
});

describe("generateValidatedJson", () => {
  test("repairs invalid model output", async () => {
    let calls = 0;
    const provider: LlmProvider = {
      name: "mock",
      async generateText() {
        calls += 1;
        return {
          provider: "mock",
          model: "mock",
          text: calls === 1 ? "not json" : '{"ok":true}',
        };
      },
    };

    const result = await generateValidatedJson({
      provider,
      request: {
        model: "mock",
        system: "",
        prompt: "",
      },
      schema: z.object({ ok: z.boolean() }),
    });

    expect(result.value).toEqual({ ok: true });
    expect(result.repairAttempts).toBe(1);
  });
});
