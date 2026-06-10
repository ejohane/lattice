import { describe, expect, test } from "bun:test";
import { parseOpenCodeOutput } from "../src/llm/providers/opencode";

describe("parseOpenCodeOutput", () => {
  test("extracts text and usage from OpenCode JSON events", () => {
    const output = [
      JSON.stringify({
        type: "step_start",
        part: { type: "step-start" },
      }),
      JSON.stringify({
        type: "text",
        part: {
          type: "text",
          text: '{"ok":true}',
        },
      }),
      JSON.stringify({
        type: "step_finish",
        part: {
          type: "step-finish",
          tokens: {
            input: 12,
            output: 3,
          },
        },
      }),
    ].join("\n");

    expect(parseOpenCodeOutput(output)).toEqual({
      text: '{"ok":true}',
      usage: {
        input_tokens: 12,
        output_tokens: 3,
      },
    });
  });

  test("throws when no text event is present", () => {
    expect(() =>
      parseOpenCodeOutput(JSON.stringify({ type: "step_finish" })),
    ).toThrow("OpenCode did not return any text output.");
  });
});
