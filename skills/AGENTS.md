# Lattice Vault Agent Guide

This is a Lattice vault: a local-first capture protocol for an
agent-maintained personal wiki.

Use `skills/AGENTS.md` as the harness-neutral entry point. Open this file before
editing the vault, then choose the relevant skill.

## Skills

Read the relevant raw markdown skill before acting:

- `ingest-captures.md`
- `maintain-wiki.md`
- `answer-from-wiki.md`
- `lint-wiki.md`

These files are ordinary markdown on purpose. They are intended to work with
Codex, Claude Code, GitHub Copilot, OpenCode, and any other agent harness that
can read files from the vault. A Lattice skill is not a provider integration or
a tool-specific package; it is a reusable operating procedure for a class of
wiki tasks.

## Mission

Maintain this vault as a compounding markdown knowledge base. Lattice captures
raw local context; agents turn selected evidence into durable wiki pages.

## Agent Contract

- Raw sources are immutable. Do not edit, rewrite, move, delete, or normalize
  files under `raw/`.
- Queue state is operational. Use `queue/pending.jsonl` to find captures that
  need ingestion, and use `lattice mark-ingested` after wiki updates.
- Generated or process state is operational. Treat `review/`, `synthesis/`,
  `daily/`, `index/`, and `exports/` as derived or process files unless the user
  explicitly asks you to curate them.
- The wiki is agent-owned. You may create and edit markdown under `wiki/`.
- `wiki/index.md` is content-oriented: it should be a map of stable topics,
  entities, projects, and useful entry points.
- `wiki/log.md` is chronological: it should record notable dated changes,
  decisions, and unresolved follow-ups.
- Preserve user-authored voice and structure where it exists. Improve clarity,
  links, citations, and organization without gratuitous rewrites.

## File Edit Boundaries

You may edit:

- `wiki/**/*.md`
- `skills/**/*.md` when the user asks to change vault skills
- `skills/AGENTS.md` when the user asks to change the vault skill guide
- `review/**/*.md` only to mark agent review notes or prepare proposed edits

You may create:

- New wiki pages under `wiki/`
- Missing `wiki/index.md` or `wiki/log.md`
- Lightweight health reports under `review/`

You must not mutate:

- `raw/**`
- `queue/**` except through `lattice mark-ingested`
- `config.json` unless the user asks
- `synthesis/runs/**`
- `exports/**`
- Any file outside the vault unless the user asks

## Citation Format

Every factual wiki addition from a capture needs a source citation.

Use capture IDs for text evidence:

```markdown
The user prefers manual review before wiki edits. [cap_20260609_150500_a1b2]
```

Use screenshot paths when visual context matters:

```markdown
The design reference showed the sidebar collapsed. [screenshot: raw/screenshots/2026-06-09/cap_20260609_150500_a1b2.png]
```

Use metadata only as supporting context:

```markdown
Captured while Safari was active on the "Docs" window. [metadata: cap_20260609_150500_a1b2]
```

When multiple captures support a claim, cite the most direct captures:

```markdown
The project direction shifted toward a capture protocol plus agent skills. [cap_1] [cap_2]
```

Do not invent capture IDs. Verify IDs from `raw/captures/**/*.json` or
`raw/log.jsonl`.

## Working Rules

- Prefer concrete, source-backed edits over broad summaries.
- Keep raw captures as evidence, not prose to be copied wholesale.
- Mark uncertainty directly: "Possibly", "Unclear", or "Needs confirmation".
- When captures contradict each other, keep both claims with dates and cite both.
- Ask the user before encoding sensitive personal, legal, medical, financial, or
  high-impact claims as durable wiki facts.
- Ask the user when the intended meaning is ambiguous and a wrong page edit would
  be costly to unwind.
- If a claim may be stale, include the last-supported date or move it to a
  "Status" or "Open questions" section.

## Default Task Flow

1. Identify the task: ingest, maintain, answer, or lint.
2. Read the relevant skill file.
3. Inspect existing wiki pages and indexes before writing.
4. Read only the needed captures and screenshots.
5. Make focused wiki edits with citations.
6. Update `wiki/index.md` and `wiki/log.md` when the change affects navigation or
   chronology.
7. Run `lattice mark-ingested <capture-id> --agent <agent-name>` for captures
   you incorporated.
8. Report what changed, what sources were used, and any unresolved uncertainty.
