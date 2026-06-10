import crypto from "node:crypto";
import { CaptureRecord, VaultPaths } from "../types";
import { toLocalDateString, timestampForFilename } from "../time";
import { saveCapture } from "../vault";
import { buildContext, captureActiveWindow } from "./context";
import { captureScreenshot } from "./screenshot";

export async function createCapture(input: {
  paths: VaultPaths;
  body: string;
  source: string;
  screenshot: boolean;
  now?: Date;
}): Promise<CaptureRecord> {
  const now = input.now ?? new Date();
  const localDate = toLocalDateString(now);
  const id = `cap_${timestampForFilename(now)}_${crypto.randomUUID().slice(0, 8)}`;
  const errors: string[] = [];

  const active = await captureActiveWindow();
  errors.push(...active.errors);

  const screenshot = await captureScreenshot({
    paths: input.paths,
    localDate,
    captureId: id,
    enabled: input.screenshot,
  });
  if (screenshot.error) {
    errors.push(screenshot.error);
  }

  const capture: CaptureRecord = {
    id,
    created_at: now.toISOString(),
    local_date: localDate,
    body: input.body,
    source: input.source,
    context: buildContext({
      active_app: active.active_app,
      active_window: active.active_window,
      screenshot_path: screenshot.path,
      errors,
    }),
  };

  await saveCapture(input.paths, capture);
  return capture;
}
