import OpenAI from "openai";
import { GenerateTextRequest, GenerateTextResult, LlmProvider } from "../provider";

export class OpenAIProvider implements LlmProvider {
  name = "openai" as const;

  async generateText(request: GenerateTextRequest): Promise<GenerateTextResult> {
    if (!process.env.OPENAI_API_KEY) {
      throw new Error("OPENAI_API_KEY is required when llm.provider is openai.");
    }

    const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    const body = {
      model: request.model,
      input: [
        {
          role: "system" as const,
          content: request.system,
        },
        {
          role: "user" as const,
          content: request.prompt,
        },
      ],
      ...(request.temperature === undefined
        ? {}
        : { temperature: request.temperature }),
    };
    const response = await client.responses.create({
      ...body,
    });

    const usage: GenerateTextResult["usage"] = {};
    if (response.usage?.input_tokens !== undefined) {
      usage.input_tokens = response.usage.input_tokens;
    }
    if (response.usage?.output_tokens !== undefined) {
      usage.output_tokens = response.usage.output_tokens;
    }

    return {
      text: response.output_text,
      provider: this.name,
      model: request.model,
      ...(Object.keys(usage).length > 0 ? { usage } : {}),
    };
  }
}
