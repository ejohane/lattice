# Lattice Icon Options

These are exploratory Raycast-style product icon directions for Lattice. Each SVG is a 512 x 512 rounded-square asset and can be tested by temporarily pointing `raycast-extension/package.json` at one of the files.

## Options

- `01-vault-lattice.svg`: Most conservative evolution of the current icon. It keeps the local document/vault metaphor and adds a small connected lattice in the lower-right. Works well at small sizes because the document silhouette is dominant. Recommended if continuity with the current Raycast icon matters.
- `02-capture-lattice.svg`: Emphasizes raw captures feeding into a knowledge graph. The stacked cards make "capture" clear, while the connected nodes carry the lattice concept. This is the strongest product story, though it is a little busier at 16 px.
- `03-wiki-grid.svg`: Frames the product as a maintained wiki page with structured links. The folded page and centered network read cleanly in Raycast, but the "capture" part is less explicit.
- `04-protocol-frame.svg`: Suggests an agent-ready protocol around structured source material, using corner brackets and a small lattice. This is the most distinctive mark, but the protocol brackets may read as developer tooling more than a personal wiki.
- `05-capture-tray.svg`: Uses an inbox/tray and descending arrow to make local capture immediate. The small upper nodes imply context being gathered before it lands in the vault. Strong for Raycast because the action is clear.
- `06-local-cube.svg`: Presents the vault as a local structured object rather than a page. The cube reads as durable storage and the front connection hints that raw material becomes organized knowledge.
- `07-lattice-l.svg`: A more brand-like monogram built from an `L` and connected nodes. It is the simplest and most recognizable at very small sizes, but it is less literal about capture.
- `08-context-aperture.svg`: Treats capture as focusing context through an aperture. This is distinctive and product-like, though the metaphor is more abstract than the tray or cube.
- `09-woven-wiki.svg`: Shows a wiki lattice as woven structure inside a compact page shape. It suggests interlinked knowledge without using a generic graph, but the fine grid is best above 32 px.

## Recommendation

Use `05-capture-tray.svg` if the Raycast entry point should feel action-oriented and immediately understandable. Use `07-lattice-l.svg` if the priority is a compact, durable product mark. From the full set, `05-capture-tray.svg` is the strongest extension icon direction, while `07-lattice-l.svg` is the strongest standalone brand direction.

The selected production icon is the refined cube direction, promoted to `assets/icon.svg` as the repo-level source of truth.

## Raycast Output Guidance

Raycast accepts SVG extension icons, and these files match the existing 512 x 512 SVG convention in this repo. The SVG files are the source assets. The `png/` folder contains 512 px previews, plus downsampled `256`, `128`, `64`, `32`, and `16` px previews for legibility checks.
