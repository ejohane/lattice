#!/usr/bin/env node
import { appendFile } from "node:fs/promises";
import semanticRelease from "semantic-release";
import { writeReleaseNotesCatalog } from "./release-notes.mjs";

const result = await semanticRelease(
  {
    dryRun: true,
  },
  {
    cwd: process.cwd(),
    env: process.env,
    stdout: process.stdout,
    stderr: process.stderr,
  },
);

const nextRelease = result && result.nextRelease ? result.nextRelease : undefined;
const releaseNotesCatalog = await writeReleaseNotesCatalog({ nextRelease });
const appBuild = process.env.GITHUB_RUN_NUMBER ?? `${Math.floor(Date.now() / 1000)}`;
const outputs = nextRelease
  ? {
      release_created: "true",
      version: nextRelease.version,
      git_tag: nextRelease.gitTag,
      app_build: appBuild,
    }
  : {
      release_created: "false",
      version: "",
      git_tag: "",
      app_build: appBuild,
    };

for (const [key, value] of Object.entries(outputs)) {
  console.log(`${key}=${value}`);
}

console.log(`release_notes_entries=${releaseNotesCatalog.entries.length}`);

if (process.env.GITHUB_OUTPUT) {
  await appendFile(
    process.env.GITHUB_OUTPUT,
    Object.entries(outputs)
      .map(([key, value]) => `${key}=${value}`)
      .join("\n") + "\n",
  );
}
