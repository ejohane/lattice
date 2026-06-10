import { open, showToast, Toast } from "@raycast/api";
import { runCli } from "./lib/run-cli";

interface PackResult {
  path: string;
  capture_count: number;
}

export default async function Command() {
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Creating Lattice pack",
  });

  try {
    const result = await runCli(["pack", "--json"]);
    const pack = JSON.parse(result.stdout) as PackResult;
    await open(pack.path);
    toast.style = Toast.Style.Success;
    toast.title = "Created Lattice pack";
    toast.message = `${pack.capture_count} capture${pack.capture_count === 1 ? "" : "s"}`;
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = "Could not create pack";
    toast.message = error instanceof Error ? error.message : String(error);
  }
}
