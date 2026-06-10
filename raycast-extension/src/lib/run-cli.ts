import { spawn } from "node:child_process";
import { getPreferences } from "./preferences";

export interface CliResult {
  stdout: string;
  stderr: string;
}

export async function runCli(args: string[], input?: string): Promise<CliResult> {
  const preferences = getPreferences();
  return new Promise((resolve, reject) => {
    const child = spawn(preferences.bunPath, ["run", "src/cli.ts", ...args], {
      cwd: preferences.projectPath,
      env: {
        ...process.env,
        LATTICE_VAULT_PATH: preferences.vaultPath,
      },
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code: number | null) => {
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(
          new Error(
            stderr.trim() ||
              stdout.trim() ||
              `lattice command failed with exit code ${code ?? "unknown"}`,
          ),
        );
      }
    });

    if (input !== undefined) {
      child.stdin.write(input);
    }
    child.stdin.end();
  });
}
