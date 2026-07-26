# Mac Markdown Editor

The macOS Lattice app is intentionally a small raw Markdown editor.

## Initial Contract

- A chosen folder is the only library boundary.
- Visible `.md` files are discovered recursively.
- The sidebar shows each file's relative path.
- Selecting a file loads its UTF-8 Markdown body verbatim.
- A leading YAML block with a root `lattice:` section is hidden and preserved
  unchanged when saving; other YAML frontmatter remains visible.
- The editor is plain, monospaced text with no Markdown rendering or mutation.
- The writing column stays centered, grows to at most 760 points, and uses
  responsive horizontal and top padding as the window changes size.
- Sidebar rows use a relaxed native source-list inset while keeping the sidebar
  directly resizable between compact and roomy widths.
- Edits autosave directly to the selected file.
- Hidden files and non-Markdown files are ignored.
- The trailing New Note button creates and selects an empty Markdown file in
  the chosen folder's root without adding frontmatter.
- New files use the first available `Untitled.md` name, then rename once from
  their first meaningful line when that line ends or the user leaves the note.
- Generated names remove heading markers, replace unsafe filename characters,
  stay within portable length limits, and receive numeric collision suffixes.
- Once automatically named, a file keeps that name when its first line changes.

## Test Coverage

Changes to the macOS file-and-editor loop should preserve:

- Recursive visible Markdown discovery.
- Verbatim UTF-8 reads and writes.
- Unique no-overwrite creation and byte-preserving automatic renames.
- Filename derivation, sanitization, length limits, and collisions.
- Selection and one-time naming behavior in the macOS app model.
- The full repository verification command:

```bash
bun run verify
```

Do not add Markdown presentation or feature behavior to this layer. New features
should establish their own boundary and tests before they affect the editor.
