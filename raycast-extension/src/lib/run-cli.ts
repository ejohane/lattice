import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { getPreferences } from "./preferences";

export interface CliResult {
  stdout: string;
  stderr: string;
}

export class CliCommandError extends Error {
  constructor(
    message: string,
    readonly stdout: string,
    readonly stderr: string,
    readonly code: number | null,
  ) {
    super(message);
    this.name = "CliCommandError";
  }
}

export async function runCli(args: string[], input?: string): Promise<CliResult> {
  const preferences = getPreferences();
  return new Promise((resolve, reject) => {
    const child = spawn(resolveExecutable(preferences.bunPath), ["run", "src/cli.ts", ...args], {
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
          new CliCommandError(
            stderr.trim() ||
              stdout.trim() ||
              `lattice command failed with exit code ${code ?? "unknown"}`,
            stdout,
            stderr,
            code,
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

function resolveExecutable(command: string): string {
  if (command.includes(path.sep)) {
    return command;
  }

  const candidates = [
    path.join(os.homedir(), ".bun", "bin", command),
    path.join("/opt/homebrew/bin", command),
    path.join("/usr/local/bin", command),
  ];

  return candidates.find((candidate) => existsSync(candidate)) ?? command;
}
