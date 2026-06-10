import { describe, expect, test } from "bun:test";
import os from "node:os";
import path from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { detectReleaseArtifact, resolveUpdateTarget, updateLattice } from "../src/update";

describe("release artifact detection", () => {
  test("maps supported platforms to release artifact names", () => {
    expect(detectReleaseArtifact("darwin", "arm64")).toBe("lattice-darwin-arm64");
    expect(detectReleaseArtifact("darwin", "x64")).toBe("lattice-darwin-x64");
    expect(detectReleaseArtifact("linux", "x64")).toBe("lattice-linux-x64");
  });

  test("rejects unsupported platforms", () => {
    expect(() => detectReleaseArtifact("win32", "x64")).toThrow("Unsupported update target");
  });
});

describe("update target resolution", () => {
  test("refuses to replace Bun when running from source", () => {
    expect(() =>
      resolveUpdateTarget({
        execPath: "/usr/local/bin/bun",
        argv: ["bun", "/repo/src/cli.ts", "update"],
      }),
    ).toThrow("Cannot self-update while running from source");
  });

  test("uses install directory when provided", () => {
    expect(
      resolveUpdateTarget({
        installDir: "/tmp/bin",
        binaryName: "lattice-dev",
        execPath: "/usr/local/bin/bun",
        argv: ["bun", "/repo/src/cli.ts", "update"],
      }),
    ).toBe("/tmp/bin/lattice-dev");
  });
});

describe("updateLattice", () => {
  test("installs from a release archive and checksum", async () => {
    const root = await tempRoot();
    const releaseDir = path.join(root, "release");
    const installDir = path.join(root, "bin");
    const artifact = detectReleaseArtifact();
    await mkdir(path.join(releaseDir, artifact), { recursive: true });
    await writeFile(path.join(releaseDir, artifact, "lattice"), "#!/bin/sh\necho updated\n", {
      mode: 0o755,
    });

    await run(["tar", "-czf", `${artifact}.tar.gz`, artifact], releaseDir);
    await run(["shasum", "-a", "256", `${artifact}.tar.gz`], releaseDir, `${artifact}.tar.gz.sha256`);

    const result = await updateLattice({
      baseUrl: `file://${releaseDir}`,
      installDir,
      binaryName: "lattice",
    });

    expect(result.artifact).toBe(artifact);
    expect(await readFile(path.join(installDir, "lattice"), "utf8")).toContain("echo updated");
  });
});

async function tempRoot(): Promise<string> {
  const root = path.join(os.tmpdir(), `lattice-update-test-${crypto.randomUUID()}`);
  await mkdir(root, { recursive: true });
  return root;
}

async function run(args: string[], cwd: string, stdoutFile?: string): Promise<void> {
  const child = Bun.spawn(args, {
    cwd,
    stdout: stdoutFile ? "pipe" : "inherit",
    stderr: "inherit",
  });
  const exitCode = await child.exited;
  if (exitCode !== 0) {
    throw new Error(`${args.join(" ")} failed with exit code ${exitCode}`);
  }

  if (stdoutFile) {
    await writeFile(path.join(cwd, stdoutFile), await new Response(child.stdout).text());
  }
}
