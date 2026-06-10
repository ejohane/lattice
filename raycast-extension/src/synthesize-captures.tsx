import { Action, ActionPanel, Form, showToast, Toast } from "@raycast/api";
import { useState } from "react";
import { runCli } from "./lib/run-cli";

interface SynthesizeValues {
  date: string;
  harness: string;
  model: string;
}

export default function SynthesizeCaptures() {
  const [isLoading, setIsLoading] = useState(false);

  async function handleSubmit(values: SynthesizeValues) {
    setIsLoading(true);
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Synthesizing captures",
    });

    try {
      const args = ["synthesize", "--date", values.date];
      if (values.harness !== "config") {
        args.push("--harness", values.harness);
      }
      if (values.model.trim()) {
        args.push("--model", values.model.trim());
      }

      const result = await runCli(args);
      toast.style = Toast.Style.Success;
      toast.title = "Synthesis complete";
      toast.message = result.stdout.trim();
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Synthesis failed";
      toast.message = error instanceof Error ? error.message : String(error);
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <Form
      isLoading={isLoading}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Run Synthesis" onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.TextField id="date" title="Date" defaultValue={today()} placeholder="YYYY-MM-DD" />
      <Form.Dropdown id="harness" title="Harness" defaultValue="config">
        <Form.Dropdown.Item value="config" title="Use Vault Config" />
        <Form.Dropdown.Item value="copilot" title="Copilot SDK" />
        <Form.Dropdown.Item value="opencode" title="OpenCode" />
        <Form.Dropdown.Item value="openai" title="OpenAI" />
        <Form.Dropdown.Item value="mock" title="Mock" />
      </Form.Dropdown>
      <Form.TextField id="model" title="Model Override" placeholder="Optional" />
    </Form>
  );
}

function today(): string {
  const date = new Date();
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}
