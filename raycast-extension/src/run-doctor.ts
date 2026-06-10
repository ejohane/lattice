import { showToast, Toast } from "@raycast/api";
import { CliCommandError, runCli } from "./lib/run-cli";

interface DoctorResult {
  ok: string[];
  warnings: string[];
  errors: string[];
}

export default async function Command() {
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Checking Lattice vault",
  });

  try {
    const result = await runCli(["doctor", "--json"]);
    const doctor = JSON.parse(result.stdout) as DoctorResult;
    toast.style = Toast.Style.Success;
    toast.title = "Vault doctor passed";
    toast.message = `${doctor.ok.length} ok, ${doctor.warnings.length} warning${doctor.warnings.length === 1 ? "" : "s"}`;
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = "Vault doctor failed";
    const doctor = parseDoctorError(error);
    toast.message = doctor
      ? `${doctor.errors.length} error${doctor.errors.length === 1 ? "" : "s"}, ${doctor.warnings.length} warning${doctor.warnings.length === 1 ? "" : "s"}`
      : error instanceof Error ? error.message : String(error);
  }
}

function parseDoctorError(error: unknown): DoctorResult | null {
  if (!(error instanceof CliCommandError) || !error.stdout.trim()) {
    return null;
  }

  try {
    return JSON.parse(error.stdout) as DoctorResult;
  } catch {
    return null;
  }
}
