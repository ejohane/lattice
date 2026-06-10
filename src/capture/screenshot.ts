import path from "node:path";
import { mkdir } from "node:fs/promises";
import { VaultPaths } from "../types";

export async function captureScreenshot(input: {
  paths: VaultPaths;
  localDate: string;
  captureId: string;
  enabled: boolean;
}): Promise<{ path: string | null; error: string | null }> {
  if (!input.enabled) {
    return { path: null, error: null };
  }

  if (process.platform !== "darwin") {
    return {
      path: null,
      error: "Screenshot capture is only implemented on macOS.",
    };
  }

  const screenshotDir = path.join(input.paths.screenshots, input.localDate);
  await mkdir(screenshotDir, { recursive: true });
  const screenshotPath = path.join(screenshotDir, `${input.captureId}.png`);
  const proc = Bun.spawn(["screencapture", "-x", screenshotPath], {
    stdout: "pipe",
    stderr: "pipe",
  });

  const [stderr, exitCode] = await Promise.all([
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exitCode !== 0) {
    return {
      path: null,
      error: `Screenshot capture failed: ${stderr.trim() || exitCode}`,
    };
  }

  return { path: path.relative(input.paths.root, screenshotPath), error: null };
}
