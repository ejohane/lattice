# Mac Markdown Editor

The macOS Lattice app is intentionally a small, source-preserving live Markdown editor.

## Initial Contract

- A chosen folder is the only library boundary.
- Visible `.md` files are discovered recursively.
- The sidebar shows each file's relative path.
- Selecting a file loads its UTF-8 Markdown body verbatim.
- A leading YAML block with a root `lattice:` section is hidden and preserved
  unchanged when saving; other YAML frontmatter remains visible.
- The editor uses a native TextKit-backed surface while the Markdown characters
  remain the canonical document.
- H1-H6 headings, bold, italic, inline code, unordered lists, and task lists
  receive live presentation.
- Markdown links render as linked labels, while pasted `http` and `https` URLs
  receive link styling without changing their source. Clicking either form
  opens an absolute web destination in the default browser; Option-click keeps
  the interaction in the editor.
- Command-K wraps a single-line selection as `[label](https://)` and selects the
  destination placeholder for immediate replacement.
- Markdown delimiters are visible only while the selection touches their
  construct and collapse as soon as the caret moves beyond it.
- The first insertion in an empty note seeds a real `# ` H1 prefix as part of
  the same native undo operation.
- Return continues bullet and task items; Return on an empty item exits its list.
- Tab indents list items and Shift-Tab outdents them; Shift-Tab at the outermost
  list level stays in the editor without changing the note.
- Rendered task controls toggle only the Markdown checkbox marker.
- The writing column stays centered, grows to at most 760 points, and uses
  responsive horizontal and top padding as the window changes size.
- Sidebar rows use a relaxed native source-list inset while keeping the sidebar
  directly resizable between compact and roomy widths.
- Edits autosave directly to the selected file.
- Hidden files and non-Markdown files are ignored.
- The trailing New Note button creates and selects an empty Markdown file in
  the chosen folder's root without adding frontmatter.
- Command-Shift-P opens a command palette containing only New Note and displays
  Command-N as its shortcut.
- Choosing New Note in the palette or pressing Command-N runs the same creation
  flow instead of opening a new app window.
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
- Exact source preservation across presentation, task toggles, undo, autosave,
  and relaunch.
- Range-local parsing during typing, with full-document presentation limited to
  initial loads and composition recovery.
- Unicode, marked-text composition, paste, rapid edits, and large-note behavior.
- The full repository verification command:

```bash
bun run verify
```

Keep file persistence, Markdown parsing, AppKit input, and visual decoration in
separate boundaries. New editor features should establish their own tests before
they affect the native surface.
