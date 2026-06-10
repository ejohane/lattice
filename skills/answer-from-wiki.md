# Skill: Answer From Wiki

Use this skill when the user asks a question that should be answered from the
vault.

## Source Priority

1. `wiki/**/*.md` for durable knowledge
2. `wiki/log.md` for chronology and decisions
3. `raw/captures/` and `raw/log.jsonl` for verification or missing context
4. `raw/screenshots/` for visual evidence
5. `daily/`, `review/`, `index/`, and `synthesis/` only as orientation

Do not answer from generated review artifacts alone when raw or wiki sources are
available.

## Steps

1. Search the wiki first.
   - Look for page titles, aliases, headings, and related terms.
   - Read the most relevant pages fully enough to understand context.

2. Verify important claims.
   - Follow capture citations to `raw/captures/` or `raw/log.jsonl` when
     precision matters.
   - Check dates for claims that may be stale.
   - Inspect screenshots only when visual details are part of the answer.

3. Answer with calibrated confidence.
   - State what the wiki says.
   - Include dates for time-sensitive facts.
   - Mention contradictions or gaps.
   - Do not invent missing links or sources.

4. Offer maintenance only when useful.
   - If the answer reveals stale pages, missing citations, or bad links, mention
     the issue.
   - Do not edit the wiki during an answer-only task unless the user asked you to
     update it.

## Citation Style in Answers

Use short source references when helpful:

```markdown
The current direction is "capture protocol plus agent skills" based on
the Lattice page and captures [cap_20260609_101500_abcd].
```

For screenshot-backed answers:

```markdown
The screenshot at `raw/screenshots/2026-06-09/cap_20260609_101500_abcd.png`
shows the relevant UI state.
```

## Uncertainty Rules

- If the wiki is silent, say so and offer to search raw captures.
- If raw captures are contradictory, say what conflicts and cite both sides.
- If the newest source is old, include "last supported by sources on
  YYYY-MM-DD".
- If a claim depends on external current facts, say the vault does not establish
  the current external state.
- Ask the user when answering would require guessing intent, identity, or a
  sensitive fact.
