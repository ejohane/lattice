import { Action, ActionPanel, Form, showToast, Toast } from "@raycast/api";
import { useState } from "react";
import { runCli } from "./lib/run-cli";

interface InstallSkillsValues {
  force: boolean;
}

interface InstallSkillsResult {
  installed: string[];
  skipped: string[];
}

export default function InstallSkills() {
  const [isLoading, setIsLoading] = useState(false);

  async function handleSubmit(values: InstallSkillsValues) {
    setIsLoading(true);
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: values.force ? "Updating skills" : "Installing skills",
    });

    try {
      const args = ["skills", "install", "--json"];
      if (values.force) {
        args.push("--force");
      }

      const result = await runCli(args);
      const parsed = JSON.parse(result.stdout) as InstallSkillsResult;
      toast.style = Toast.Style.Success;
      toast.title = values.force ? "Skills updated" : "Skills installed";
      toast.message = `${parsed.installed.length} installed, ${parsed.skipped.length} skipped`;
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Could not install skills";
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
          <Action.SubmitForm title="Install Skills" onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.Checkbox id="force" title="Force" label="Overwrite existing skill files" />
    </Form>
  );
}
