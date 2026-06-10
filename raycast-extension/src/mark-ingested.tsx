import { Action, ActionPanel, Form, showToast, Toast } from "@raycast/api";
import { useState } from "react";
import { runCli } from "./lib/run-cli";

interface MarkIngestedValues {
  captureIds: string;
  agent: string;
}

export default function MarkIngested() {
  const [isLoading, setIsLoading] = useState(false);

  async function handleSubmit(values: MarkIngestedValues) {
    const ids = values.captureIds
      .split(/[,\s]+/)
      .map((id) => id.trim())
      .filter(Boolean);

    if (ids.length === 0) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Add at least one capture ID",
      });
      return;
    }

    setIsLoading(true);
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Marking captures ingested",
    });

    try {
      const agent = values.agent.trim() || "raycast";
      await runCli(["mark-ingested", ...ids, "--agent", agent, "--json"]);
      toast.style = Toast.Style.Success;
      toast.title = "Marked ingested";
      toast.message = `${ids.length} capture${ids.length === 1 ? "" : "s"}`;
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Could not mark ingested";
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
          <Action.SubmitForm title="Mark Ingested" onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.TextArea id="captureIds" title="Capture IDs" placeholder="cap_..." autoFocus />
      <Form.TextField id="agent" title="Agent" defaultValue="raycast" />
    </Form>
  );
}
