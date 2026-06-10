import { CaptureContext } from "../types";

const OSASCRIPT_PATH = "/usr/bin/osascript";

export async function captureActiveWindow(): Promise<{
  active_app: string | null;
  active_window: string | null;
  errors: string[];
}> {
  if (process.platform !== "darwin") {
    return {
      active_app: null,
      active_window: null,
      errors: ["Active app/window capture is only implemented on macOS."],
    };
  }

  const script = `
tell application "System Events"
  set frontApp to first application process whose frontmost is true
  set appName to name of frontApp
  set windowName to ""
  try
    set windowName to name of front window of frontApp
  end try
  return appName & linefeed & windowName
end tell
`;

  const proc = Bun.spawn([OSASCRIPT_PATH, "-e", script], {
    stdout: "pipe",
    stderr: "pipe",
  });

  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exitCode !== 0) {
    return {
      active_app: null,
      active_window: null,
      errors: [`Active window capture failed: ${stderr.trim() || exitCode}`],
    };
  }

  const [activeApp, activeWindow] = stdout.split(/\r?\n/);
  return {
    active_app: activeApp?.trim() || null,
    active_window: activeWindow?.trim() || null,
    errors: [],
  };
}

export function buildContext(input: {
  active_app: string | null;
  active_window: string | null;
  screenshot_path: string | null;
  errors: string[];
}): CaptureContext {
  return {
    active_app: input.active_app,
    active_window: input.active_window,
    screenshot_path: input.screenshot_path,
    metadata_errors: input.errors,
  };
}
