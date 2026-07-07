# Mac Markdown Editor

Lattice stores ordinary Markdown files on disk. The mac editor should make those
files pleasant to write without changing the storage format into rich text or a
private document model.

## Rendering Contract

- Markdown source remains the saved document content.
- The editor live-renders Markdown while editing plain text.
- Inactive Markdown tokens are visually minimized or hidden.
- Tokens become visible and editable when the insertion point moves into the
  Markdown construct.
- Unordered list markers render as bullet glyphs when inactive.
- Active list markers remain visible as source text.
- List item spacing matches list line spacing, not the normal paragraph spacing.
- The formatting toolbar can insert Markdown task-list items.
- Clicking or tapping a task-list checkbox prefix toggles `[ ]` and `[x]`.
- Inline bold, italic, code, and links style their content while hiding inactive
  syntax tokens.
- Pipe tables render as bordered tables when inactive, and show the Markdown
  source when the insertion point moves into the table.
- Complete pipe tables are normalized to evenly padded Markdown source columns
  after the insertion point leaves the table.
- Fenced code blocks do not receive inline Markdown styling.
- Return continues unordered, ordered, and task lists.
- Return on an empty list item exits the list.

## Test Coverage

Changes to `MarkdownAttributedRenderer`, `MarkdownTextEditor`, or
`MarkdownListContinuation` should preserve:

- Renderer attribute tests in `apps/lattice/Tests/LatticeSharedTests`.
- Parser and editing tests in `apps/lattice/Tests/LatticeCoreTests`.
- The full repository verification command:

```bash
bun run verify
```

Prefer adding pure `LatticeEditor` tests for editing behavior before adding UI
tests. AppKit-specific tests should cover attributed-string rendering attributes
or native text view integration that cannot be represented as pure string edits.
