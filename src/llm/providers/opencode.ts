import { existsSync } from "node:fs";
import path from "node:path";
import { homedir } from "node:os";
import { GenerateTextRequest, GenerateTextResult, LlmProvider } from "../provider";

export class OpenCodeProvider implements LlmProvider {
  name = "opencode" as const;

  async generateText(request: GenerateTextRequest): Promise<GenerateTextResult> {
    const prompt = `${request.system}\n\n${request.prompt}`;
    const proc = Bun.spawn(
      [
        resolveOpenCodeCommand(),
        "run",
        "--model",
        request.model,
        "--format",
        "json",
        "--agent",
        "build",
        prompt,
      ],
      {
        stdout: "pipe",
        stderr: "pipe",
        env: process.env,
      },
    );

    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ]);

    if (exitCode !== 0) {
      throw new Error(
        `OpenCode failed: ${stderr.trim() || stdout.trim() || exitCode}`,
      );
    }

    const parsed = parseOpenCodeOutput(stdout);
    return {
      text: parsed.text,
      provider: this.name,
      model: request.model,
      ...(parsed.usage ? { usage: parsed.usage } : {}),
    };
  }
}

export function parseOpenCodeOutput(output: string): {
  text: string;
  usage?: GenerateTextResult["usage"];
} {
  const textParts: string[] = [];
  const usage: GenerateTextResult["usage"] = {};

  for (const line of output.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }

    let event: unknown;
    try {
      event = JSON.parse(trimmed);
    } catch {
      continue;
    }

    if (!event || typeof event !== "object") {
      continue;
    }

    const record = event as {
      type?: string;
      part?: {
        type?: string;
        text?: string;
        tokens?: {
          input?: number;
          output?: number;
        };
      };
    };

    if (record.type === "text" && record.part?.type === "text") {
      textParts.push(record.part.text ?? "");
    }

    if (record.type === "step_finish" && record.part?.tokens) {
      if (record.part.tokens.input !== undefined) {
        usage.input_tokens = record.part.tokens.input;
      }
      if (record.part.tokens.output !== undefined) {
        usage.output_tokens = record.part.tokens.output;
      }
    }
  }

  const text = textParts.join("").trim();
  if (!text) {
    throw new Error("OpenCode did not return any text output.");
  }

  return {
    text,
    ...(Object.keys(usage).length > 0 ? { usage } : {}),
  };
}

function resolveOpenCodeCommand(): string {
  if (process.env.OPENCODE_BIN) {
    return process.env.OPENCODE_BIN;
  }

  const homeBin = path.join(homedir(), ".opencode", "bin", "opencode");
  if (existsSync(homeBin)) {
    return homeBin;
  }

  return "opencode";
}
