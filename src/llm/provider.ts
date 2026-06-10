import { ProviderName } from "../types";
import { CopilotProvider } from "./providers/copilot";
import { MockProvider } from "./providers/mock";
import { OpenCodeProvider } from "./providers/opencode";
import { OpenAIProvider } from "./providers/openai";

export interface GenerateTextRequest {
  model: string;
  system: string;
  prompt: string;
  temperature?: number;
}

export interface GenerateTextResult {
  text: string;
  provider: string;
  model: string;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
  };
}

export interface LlmProvider {
  name: ProviderName;
  generateText(request: GenerateTextRequest): Promise<GenerateTextResult>;
}

export function createLlmProvider(name: ProviderName): LlmProvider {
  if (name === "copilot") {
    return new CopilotProvider();
  }

  if (name === "openai") {
    return new OpenAIProvider();
  }

  if (name === "opencode") {
    return new OpenCodeProvider();
  }

  return new MockProvider();
}
