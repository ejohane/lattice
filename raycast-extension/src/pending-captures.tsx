import { Action, ActionPanel, List, showToast, Toast } from "@raycast/api";
import { useCallback, useEffect, useState } from "react";
import { openVaultPath } from "./lib/open-path";
import { runCli } from "./lib/run-cli";

interface PendingEntry {
  capture_id: string;
  created_at: string;
  local_date: string;
  source: string;
  raw_capture_path: string;
  screenshot_path: string | null;
}

export default function PendingCaptures() {
  const [entries, setEntries] = useState<PendingEntry[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const load = useCallback(async () => {
    setIsLoading(true);
    try {
      const result = await runCli(["pending", "--json"]);
      setEntries(JSON.parse(result.stdout) as PendingEntry[]);
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Could not list pending captures",
        message: error instanceof Error ? error.message : String(error),
      });
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function markIngested(entry: PendingEntry) {
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Marking capture ingested",
      message: entry.capture_id,
    });

    try {
      await runCli(["mark-ingested", entry.capture_id, "--agent", "raycast", "--json"]);
      toast.style = Toast.Style.Success;
      toast.title = "Marked ingested";
      toast.message = entry.capture_id;
      await load();
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Could not mark ingested";
      toast.message = error instanceof Error ? error.message : String(error);
    }
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search pending captures">
      {entries.length === 0 && !isLoading ? (
        <List.EmptyView title="No Pending Captures" description="The Lattice queue is clear." />
      ) : (
        entries.map((entry) => (
          <List.Item
            key={entry.capture_id}
            title={entry.capture_id}
            subtitle={entry.raw_capture_path}
            accessories={[
              { text: entry.source },
              { text: entry.local_date },
            ]}
            actions={
              <ActionPanel>
                <ActionPanel.Section>
                  <Action title="Open Raw Capture" onAction={() => openVaultPath(entry.raw_capture_path)} />
                  {entry.screenshot_path ? (
                    <Action title="Open Screenshot" onAction={() => openVaultPath(entry.screenshot_path!)} />
                  ) : null}
                  <Action title="Mark Ingested" onAction={() => markIngested(entry)} />
                </ActionPanel.Section>
                <ActionPanel.Section>
                  <Action.CopyToClipboard title="Copy Capture ID" content={entry.capture_id} />
                  <Action title="Refresh" onAction={load} />
                </ActionPanel.Section>
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}
