# Skill: Lint and Health-Check Wiki

Use this skill to inspect wiki quality without changing raw evidence.

## Scope

Check:

- Missing or weak citations
- Broken wiki links
- Orphan pages
- Duplicate pages or aliases
- Stale current-state claims
- Contradictions that are not acknowledged
- Missing `wiki/index.md` entries
- Missing chronological entries in `wiki/log.md`

Do not mutate `raw/` or `queue/` by hand.

## Steps

1. Inventory markdown pages.
   - List `wiki/**/*.md`.
   - Identify `wiki/index.md` and `wiki/log.md`.
   - Build a simple map of page titles, paths, and links.

2. Check links.
   - Verify relative markdown links point to existing files.
   - Flag links to missing headings only when the heading is important.
   - Flag orphan pages that are not linked from index, log, or another page.

3. Check citations.
   - Find factual paragraphs without capture IDs where citations are expected.
   - Verify cited capture IDs exist in `raw/captures/` or `raw/log.jsonl`.
   - Verify screenshot paths exist when cited.

4. Check freshness.
   - Look for "current", "now", "today", "latest", and status sections without
     dates.
   - Compare against newer captures when the page topic appears in raw sources.

5. Check contradictions.
   - Search for conflicting status words such as "decided", "reversed",
     "deprecated", "blocked", and "done".
   - Flag contradictions that do not include dates or source citations.

6. Report or fix.
   - If the user asked for a report, write findings only.
   - If the user asked for fixes, edit `wiki/` and optionally write a health
     report under `review/`.

## Health Report Format

Use this format for reports in chat or under `review/`:

```markdown
# Wiki Health Check - YYYY-MM-DD

## Broken Links

## Missing Citations

## Orphan Pages

## Duplicate or Conflicting Pages

## Stale Claims

## Recommended Fixes
```

## Severity Guide

- High: unsupported or contradictory claims likely to affect future decisions.
- Medium: broken navigation, missing citations on important facts, duplicate
  pages.
- Low: style drift, weak summaries, minor orphan pages.

## Ask the User When

- A fix would delete or merge meaningful user-authored content.
- A stale claim may still be intentionally preserved.
- A contradiction involves preference, identity, sensitive facts, or major
  decisions.
