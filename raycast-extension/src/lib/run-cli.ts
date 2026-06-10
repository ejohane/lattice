import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { resolveLatticePath, resolveVaultPath } from "./lattice-config";

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
  const latticePath = resolveExecutable(resolveLatticePath());
  const vaultPath = resolveVaultPath();
  return new Promise((resolve, reject) => {
    const child = spawn(latticePath, args, {
      env: {
        ...process.env,
        PATH: defaultPath(process.env.PATH),
        LATTICE_VAULT_PATH: vaultPath,
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
    path.join("/opt/homebrew/bin", command),
    path.join("/usr/local/bin", command),
    path.join(os.homedir(), ".local", "bin", command),
    path.join(os.homedir(), ".bun", "bin", command),
  ];

  return candidates.find((candidate) => existsSync(candidate)) ?? command;
}

function defaultPath(current: string | undefined): string {
  const defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"];
  const parts = new Set((current ?? "").split(":").filter(Boolean));
  for (const item of defaults) {
    parts.add(item);
  }
  return [...parts].join(":");
}
