# Skill: Maintain Wiki

Use this skill for organizing, linking, pruning, and improving existing wiki
pages.

## Wiki Ownership

The wiki is the durable agent-owned layer:

- `wiki/index.md`: content-oriented map and entry point
- `wiki/log.md`: chronological record of meaningful changes and decisions
- `wiki/pages/**/*.md`: topic, project, person, system, and reference pages

Do not edit raw evidence to make the wiki look cleaner. Fix the wiki instead.

## Maintenance Tasks

Use this skill for:

- Linking related pages
- Splitting pages that have grown too broad
- Merging duplicate pages
- Updating stale status sections
- Adding missing citations
- Moving unresolved facts into open questions
- Creating or repairing index entries
- Recording dated decisions in `wiki/log.md`

## Steps

1. Inspect current structure.
   - Read `wiki/index.md` if it exists.
   - Search `wiki/pages/` for duplicate titles, aliases, and headings.
   - Check backlinks by searching for page names and aliases.

2. Preserve meaning.
   - Do not delete sourced facts unless they are duplicated elsewhere.
   - If you move content, keep citations attached to the moved claim.
   - If a section is stale, mark it with date context instead of erasing history.

3. Improve page shape.
   - Put current state near the top.
   - Keep decisions and rationale together.
   - Move dated events to `wiki/log.md` when they are mainly chronological.
   - Move broad background to topic pages when project pages become cluttered.

4. Repair links.
   - Link existing pages with relative markdown links.
   - Create missing pages only when they will hold durable knowledge.
   - Remove or replace links to pages that do not exist.

5. Update index and log.
   - `wiki/index.md` should help a future agent or user find important content.
   - `wiki/log.md` should include dates, brief descriptions, and citations for
     material changes or decisions.

## Page Conventions

Recommended page skeleton:

```markdown
# Page Title

Brief current summary with citations where needed.

## Current State

## Decisions

## Open Questions

## Related
```

Use only the sections that add value. Do not force every page into the skeleton.

## Handling Contradictions and Staleness

- Contradictions: include both sourced statements and identify which one appears
  newer or more authoritative.
- Stale claims: write "As of YYYY-MM-DD" or move the older claim to a dated
  history section.
- Missing citation: search captures for support. If none is found, mark the line
  as uncited or ask the user before keeping it as fact.
- Orphan page: either link it from `wiki/index.md` or a related page under
  `wiki/pages/`, merge it, or explain why it remains standalone.

## Ask the User When

- A merge would discard nuance.
- A contradiction changes an important decision.
- A page contains sensitive personal information and the desired retention policy
  is unclear.
- You cannot find evidence for a claim that affects future decisions.
