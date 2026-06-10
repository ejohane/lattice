import {
  CopilotClient,
  type PermissionRequest,
  type PermissionRequestResult,
} from "@github/copilot-sdk";
import { GenerateTextRequest, GenerateTextResult, LlmProvider } from "../provider";

export class CopilotProvider implements LlmProvider {
  name = "copilot" as const;

  async generateText(request: GenerateTextRequest): Promise<GenerateTextResult> {
    const client = new CopilotClient({
      workingDirectory: process.cwd(),
      logLevel: "error",
    });

    await client.start();
    try {
      const session = await client.createSession({
        model: request.model,
        availableTools: [],
        excludedTools: ["builtin:*", "mcp:*", "custom:*"],
        skipCustomInstructions: true,
        enableConfigDiscovery: false,
        onPermissionRequest: denyAllPermissions,
      });

      try {
        const response = await session.sendAndWait(
          {
            prompt: `${request.system}\n\n${request.prompt}`,
          },
          120_000,
        );

        return {
          text: response?.data.content ?? "",
          provider: this.name,
          model: request.model,
        };
      } finally {
        await session.disconnect();
      }
    } finally {
      await client.stop();
    }
  }
}

function denyAllPermissions(
  request: PermissionRequest,
): PermissionRequestResult {
  return {
    kind: "reject",
    feedback: `The synthesis client does not allow tool use. Denied ${request.kind}.`,
  };
}
