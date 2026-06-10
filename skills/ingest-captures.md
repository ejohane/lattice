# Skill: Ingest Captures

Use this skill to turn raw Lattice captures into durable wiki updates.

## Inputs

Primary evidence lives in:

- `queue/pending.jsonl`
- `raw/log.jsonl`
- `raw/captures/YYYY-MM-DD/<capture-id>.json`
- `raw/screenshots/YYYY-MM-DD/*`

Review artifacts may exist in:

- `daily/YYYY-MM-DD.md`
- `review/**/*.md`
- `review/**/*.json`
- `synthesis/runs/**`

Review artifacts can help you orient, but they are not the source of truth. Cite
capture IDs and screenshot paths, not synthesis run IDs.

## Steps

1. Choose the capture set.
   - If the user did not specify a set, inspect `queue/pending.jsonl`.
   - If the user gave capture IDs, find their `raw_capture_path` entries in
     `queue/pending.jsonl` or locate them under `raw/captures/`.
   - If the user gave a date, inspect `raw/captures/<date>/`.
   - If the user gave a topic, search `raw/captures/`, `raw/log.jsonl`, and
     `wiki/` for the topic first.
   - If there is a review proposal, compare it with the raw capture records.

2. Extract candidate knowledge.
   - Durable facts: preferences, decisions, project direction, definitions,
     recurring people, systems, constraints, and stable links.
   - Chronological facts: dated decisions, milestones, changes, and follow-ups.
   - Tasks: only keep them if they matter beyond the immediate capture.
   - Ephemera: leave it in raw captures unless the user asks.

3. Find existing homes.
   - Search `wiki/` for related pages, aliases, and headings.
   - Prefer updating an existing page over creating a near-duplicate.
   - Create a new page when the topic is stable, likely to recur, and does not
     fit an existing page.

4. Edit wiki pages.
   - Add concise, source-backed prose.
   - Use capture citations for claims.
   - Add screenshot citations only when visual evidence matters.
   - Put ambiguous items under "Open questions" or "Unconfirmed".

5. Update navigation and chronology.
   - Update `wiki/index.md` when you add or substantially rename pages.
   - Update `wiki/log.md` for dated decisions, milestones, contradictions, or
     important maintenance actions.

6. Mark completed captures.
   - Only mark captures ingested after the relevant wiki edits are complete.
   - Run `lattice mark-ingested <capture-id> --agent <agent-name>`.
   - Do not edit `queue/pending.jsonl` or `queue/ingested.jsonl` by hand.

7. Report outcome.
   - List edited pages.
   - List capture IDs used.
   - Note skipped captures and why.
   - Note questions for the user.

## Citation Rules

Use capture IDs inline:

```markdown
The user wants Lattice to stay small: capture CLI, vault protocol, and queue state. [cap_20260609_101500_abcd]
```

Use screenshot paths when needed:

```markdown
The captured UI showed the queue grouped by local date. [screenshot: raw/screenshots/2026-06-09/cap_20260609_101500_abcd.png]
```

Use metadata sparingly:

```markdown
This was captured from a terminal session. [metadata: cap_20260609_101500_abcd]
```

If a claim combines sources, cite each source at the sentence or bullet where it
is used.

## Handling Problems

- Missing capture file: do not cite it. Add a note to the final report.
- Missing screenshot: cite the capture and say the screenshot is unavailable.
- Contradiction: keep both claims with dates and sources, then add the current
  best interpretation only if evidence supports it.
- Stale claim: keep historical context, add "As of YYYY-MM-DD" or move the
  current state to a separate line.
- Sensitive claim: ask the user before making it durable.
- Low-confidence interpretation: write it as a question, not a fact.
