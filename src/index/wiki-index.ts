import path from "node:path";
import { readFile } from "node:fs/promises";
import { PageIndexEntry, TaxonomyIndexEntry, VaultPaths } from "../types";
import { listMarkdownFiles, writeJson } from "../vault";

export interface WikiIndex {
  pages: PageIndexEntry[];
  taxonomy: TaxonomyIndexEntry[];
  aliases: Record<string, string>;
}

export async function rebuildWikiIndex(paths: VaultPaths): Promise<WikiIndex> {
  const files = await listMarkdownFiles(paths.wiki);
  const pages = await Promise.all(
    files.map(async (file) => {
      const relPath = path.relative(paths.wiki, file);
      const content = await readFile(file, "utf8");
      return parsePageIndexEntry(relPath, content);
    }),
  );

  const taxonomy = buildTaxonomy(pages);
  const aliases = buildAliases(pages);

  await writeJson(path.join(paths.index, "pages.json"), pages);
  await writeJson(path.join(paths.index, "taxonomy.json"), taxonomy);
  await writeJson(path.join(paths.index, "aliases.json"), aliases);

  return { pages, taxonomy, aliases };
}

function parsePageIndexEntry(relPath: string, content: string): PageIndexEntry {
  const frontmatter = parseFrontmatter(content);
  const filenameTitle = path.basename(relPath, ".md").replace(/[-_]/g, " ");
  const h1 = content.match(/^#\s+(.+)$/m)?.[1]?.trim();
  const title = frontmatter.title ?? h1 ?? toTitleCase(filenameTitle);
  const summary =
    frontmatter.summary ??
    firstParagraph(content.replace(/^---[\s\S]*?---\s*/, "")) ??
    "";

  return {
    id: slugify(relPath.replace(/\.md$/, "")),
    title,
    path: relPath,
    kind: frontmatter.kind ?? null,
    aliases: frontmatter.aliases,
    summary: summary.slice(0, 320),
  };
}

function buildTaxonomy(pages: PageIndexEntry[]): TaxonomyIndexEntry[] {
  const counts = new Map<string, number>();
  for (const page of pages) {
    const dir = path.dirname(page.path);
    if (dir === ".") {
      continue;
    }

    const parts = dir.split(path.sep);
    for (let i = 0; i < parts.length; i += 1) {
      const taxonomyPath = parts.slice(0, i + 1).join("/");
      counts.set(taxonomyPath, (counts.get(taxonomyPath) ?? 0) + 1);
    }
  }

  return [...counts.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([taxonomyPath, pageCount]) => ({
      path: taxonomyPath,
      page_count: pageCount,
      description: null,
    }));
}

function buildAliases(pages: PageIndexEntry[]): Record<string, string> {
  const aliases: Record<string, string> = {};
  for (const page of pages) {
    aliases[page.title.toLowerCase()] = page.path;
    for (const alias of page.aliases) {
      aliases[alias.toLowerCase()] = page.path;
    }
  }
  return aliases;
}

function parseFrontmatter(content: string): {
  title?: string;
  kind?: string;
  summary?: string;
  aliases: string[];
} {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match?.[1]) {
    return { aliases: [] };
  }

  const lines = match[1].split("\n");
  const out: {
    title?: string;
    kind?: string;
    summary?: string;
    aliases: string[];
  } = { aliases: [] };

  let inAliases = false;
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }

    if (trimmed === "aliases:") {
      inAliases = true;
      continue;
    }

    if (inAliases && trimmed.startsWith("- ")) {
      out.aliases.push(unquote(trimmed.slice(2).trim()));
      continue;
    }

    inAliases = false;
    const keyValue = trimmed.match(/^([a-zA-Z_]+):\s*(.*)$/);
    if (!keyValue) {
      continue;
    }

    const key = keyValue[1];
    const value = unquote(keyValue[2] ?? "");
    if (key === "title") {
      out.title = value;
    } else if (key === "kind") {
      out.kind = value;
    } else if (key === "summary") {
      out.summary = value;
    }
  }

  return out;
}

function firstParagraph(content: string): string | null {
  const paragraphs = content
    .split(/\n{2,}/)
    .map((paragraph) => paragraph.trim())
    .filter((paragraph) => paragraph && !paragraph.startsWith("#"));

  return paragraphs[0] ?? null;
}

function unquote(value: string): string {
  return value.replace(/^["']|["']$/g, "");
}

function toTitleCase(value: string): string {
  return value.replace(/\b\w/g, (char) => char.toUpperCase());
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}
