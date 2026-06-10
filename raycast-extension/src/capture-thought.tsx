import { Action, ActionPanel, closeMainWindow, Form, showToast, Toast } from "@raycast/api";
import { useState } from "react";
import { runCli } from "./lib/run-cli";

interface CaptureValues {
  body: string;
  includeScreenshot: boolean;
}

export default function CaptureThought() {
  const [isLoading, setIsLoading] = useState(false);

  async function handleSubmit(values: CaptureValues) {
    if (!values.body.trim()) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Write a note first",
      });
      return;
    }

    setIsLoading(true);
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Saving capture",
    });

    try {
      const args = ["capture", "--stdin", "--source", "raycast", "--json"];
      if (!values.includeScreenshot) {
        args.push("--no-screenshot");
      }
      await closeMainWindow({ clearRootSearch: true });
      await new Promise((resolve) => setTimeout(resolve, 200));
      const result = await runCli(args, values.body);
      const parsed = JSON.parse(result.stdout) as { id: string };
      toast.style = Toast.Style.Success;
      toast.title = "Saved capture";
      toast.message = parsed.id;
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Capture failed";
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
          <Action.SubmitForm title="Save Capture" onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.TextArea id="body" title="Body" placeholder="Capture a thought or source note" autoFocus />
      <Form.Checkbox id="includeScreenshot" title="Screenshot" label="Capture screenshot" defaultValue />
    </Form>
  );
}
