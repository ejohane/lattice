import { z } from "zod";

export const ProviderNameSchema = z.enum(["copilot", "opencode", "openai", "mock"]);
export type ProviderName = z.infer<typeof ProviderNameSchema>;

export const CaptureContextSchema = z.object({
  active_app: z.string().nullable(),
  active_window: z.string().nullable(),
  screenshot_path: z.string().nullable(),
  metadata_errors: z.array(z.string()),
});

export type CaptureContext = z.infer<typeof CaptureContextSchema>;

export const CaptureRecordSchema = z.object({
  schema_version: z.literal(1),
  kind: z.literal("capture"),
  id: z.string(),
  created_at: z.string(),
  local_date: z.string(),
  body: z.string(),
  source: z.string(),
  context: CaptureContextSchema,
});

export type CaptureRecord = z.infer<typeof CaptureRecordSchema>;

export const QueueEntrySchema = z.object({
  schema_version: z.literal(1),
  capture_id: z.string(),
  created_at: z.string(),
  local_date: z.string(),
  source: z.string(),
  raw_capture_path: z.string(),
  screenshot_path: z.string().nullable(),
});

export type QueueEntry = z.infer<typeof QueueEntrySchema>;

export const IngestedEntrySchema = QueueEntrySchema.extend({
  ingested_at: z.string(),
  agent: z.string(),
});

export type IngestedEntry = z.infer<typeof IngestedEntrySchema>;

export const AppConfigSchema = z.object({
  protocol_version: z.literal(1),
  llm: z.object({
    provider: ProviderNameSchema,
    model: z.string(),
    temperature: z.number().min(0).max(2),
  }),
  capture: z.object({
    screenshots_default: z.boolean(),
  }),
});

export type AppConfig = z.infer<typeof AppConfigSchema>;

export const DEFAULT_CONFIG: AppConfig = {
  protocol_version: 1,
  llm: {
    provider: "copilot",
    model: "gpt-5.4-mini",
    temperature: 0,
  },
  capture: {
    screenshots_default: true,
  },
};

export interface VaultPaths {
  root: string;
  raw: string;
  rawLog: string;
  captures: string;
  screenshots: string;
  queue: string;
  pendingQueue: string;
  ingestedQueue: string;
  daily: string;
  wiki: string;
  wikiPages: string;
  skills: string;
  exports: string;
  packs: string;
  index: string;
  review: string;
  synthesis: string;
  synthesisRuns: string;
  config: string;
}

export interface PageIndexEntry {
  id: string;
  title: string;
  path: string;
  kind: string | null;
  aliases: string[];
  summary: string;
}

export interface TaxonomyIndexEntry {
  path: string;
  page_count: number;
  description: string | null;
}
