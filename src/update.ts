import { createHash } from "node:crypto";
import path from "node:path";
import { chmod, copyFile, mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";

const DEFAULT_REPO = "ejohane/lattice";

export interface UpdateOptions {
  repo?: string;
  version?: string;
  installDir?: string;
  binaryName?: string;
  baseUrl?: string;
}

export interface UpdateResult {
  artifact: string;
  archiveUrl: string;
  checksumUrl: string;
  installedPath: string;
  version: string;
}

export function detectReleaseArtifact(
  platform: NodeJS.Platform = process.platform,
  arch: string = process.arch,
): string {
  if (platform === "darwin") {
    if (arch === "arm64") {
      return "lattice-darwin-arm64";
    }
    if (arch === "x64") {
      return "lattice-darwin-x64";
    }
  }

  if (platform === "linux" && arch === "x64") {
    return "lattice-linux-x64";
  }

  throw new Error(`Unsupported update target: ${platform}/${arch}`);
}

export function resolveUpdateTarget(options: {
  installDir?: string;
  binaryName?: string;
  execPath?: string;
  argv?: string[];
} = {}): string {
  const argv = options.argv ?? process.argv;
  const execPath = options.execPath ?? process.execPath;
  const runningFromSource = argv[1]?.endsWith(".ts") ?? false;

  if (options.installDir) {
    return path.join(
      path.resolve(options.installDir),
      options.binaryName ?? path.basename(execPath) ?? "lattice",
    );
  }

  if (runningFromSource) {
    throw new Error(
      "Cannot self-update while running from source. Build/install a binary first, or pass --install-dir.",
    );
  }

  return path.resolve(execPath);
}

export async function updateLattice(options: UpdateOptions = {}): Promise<UpdateResult> {
  const repo = options.repo ?? DEFAULT_REPO;
  const version = options.version ?? "latest";
  const artifact = detectReleaseArtifact();
  const archiveName = `${artifact}.tar.gz`;
  const checksumName = `${archiveName}.sha256`;
  const baseUrl = resolveDownloadBaseUrl({ repo, version, baseUrl: options.baseUrl });
  const archiveUrl = `${baseUrl}/${archiveName}`;
  const checksumUrl = `${baseUrl}/${checksumName}`;
  const installedPath = resolveUpdateTarget(options);
  const installTempPath = path.join(
    path.dirname(installedPath),
    `.lattice-update-${process.pid}-${Date.now()}`,
  );
  const tempDir = await mkdtemp(path.join(tmpdir(), "lattice-update-"));

  try {
    const archivePath = path.join(tempDir, archiveName);
    const checksumPath = path.join(tempDir, checksumName);
    await downloadToFile(archiveUrl, archivePath);
    await downloadToFile(checksumUrl, checksumPath);
    await verifyChecksum(archivePath, checksumPath);
    await extractArchive(archivePath, tempDir);

    const extractedBinary = path.join(tempDir, artifact, "lattice");
    await mkdir(path.dirname(installedPath), { recursive: true });
    await copyFile(extractedBinary, installTempPath);
    await chmod(installTempPath, 0o755);
    await rename(installTempPath, installedPath);
  } finally {
    await rm(installTempPath, { force: true });
    await rm(tempDir, { recursive: true, force: true });
  }

  return {
    artifact,
    archiveUrl,
    checksumUrl,
    installedPath,
    version,
  };
}

function resolveDownloadBaseUrl(options: {
  repo: string;
  version: string;
  baseUrl?: string | undefined;
}): string {
  if (options.baseUrl) {
    return options.baseUrl.replace(/\/+$/, "");
  }

  if (options.version === "latest") {
    return `https://github.com/${options.repo}/releases/latest/download`;
  }

  return `https://github.com/${options.repo}/releases/download/${options.version}`;
}

async function downloadToFile(url: string, filePath: string): Promise<void> {
  if (url.startsWith("file://")) {
    await writeFile(filePath, await readFile(new URL(url)));
    return;
  }

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Download failed (${response.status}): ${url}`);
  }

  await writeFile(filePath, Buffer.from(await response.arrayBuffer()));
}

async function verifyChecksum(archivePath: string, checksumPath: string): Promise<void> {
  const checksumText = await readFile(checksumPath, "utf8");
  const expected = checksumText.trim().split(/\s+/)[0]?.toLowerCase();
  if (!expected || !/^[a-f0-9]{64}$/.test(expected)) {
    throw new Error(`Invalid checksum file: ${checksumPath}`);
  }

  const actual = createHash("sha256")
    .update(await readFile(archivePath))
    .digest("hex");

  if (actual !== expected) {
    throw new Error(`Checksum mismatch for ${path.basename(archivePath)}`);
  }
}

async function extractArchive(archivePath: string, destination: string): Promise<void> {
  const child = Bun.spawn(["tar", "-xzf", archivePath, "-C", destination], {
    stderr: "pipe",
    stdout: "pipe",
  });
  const exitCode = await child.exited;
  if (exitCode !== 0) {
    const stderr = await new Response(child.stderr).text();
    throw new Error(`Failed to extract archive: ${stderr.trim()}`);
  }
}
