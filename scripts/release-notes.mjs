#!/usr/bin/env node
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const defaultOutputPath = "apps/lattice/Sources/LatticeShared/Resources/ReleaseNotes.json";
const defaultRepository = "ejohane/lattice";

export async function writeReleaseNotesCatalog({
  nextRelease,
  outputPath = defaultOutputPath,
  repository = process.env.GITHUB_REPOSITORY || defaultRepository,
  token = process.env.GITHUB_TOKEN,
  now = new Date(),
} = {}) {
  const generatedAt = now.toISOString();
  const entriesByTag = new Map();

  for (const release of await fetchGitHubReleases({ repository, token })) {
    if (!release.tag_name || release.draft) {
      continue;
    }

    entriesByTag.set(release.tag_name, {
      version: normalizeVersion(release.tag_name, release.name),
      tagName: release.tag_name,
      publishedAt: release.published_at || release.created_at || null,
      url: release.html_url || null,
      sections: parseReleaseSections(release.body || ""),
    });
  }

  if (nextRelease) {
    entriesByTag.set(nextRelease.gitTag, {
      version: nextRelease.version,
      tagName: nextRelease.gitTag,
      publishedAt: generatedAt,
      url: releaseURL(repository, nextRelease.gitTag),
      sections: parseReleaseSections(nextRelease.notes || ""),
    });
  }

  const catalog = {
    schemaVersion: 1,
    generatedAt,
    repository,
    entries: Array.from(entriesByTag.values()).sort(compareEntries),
  };

  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(catalog, null, 2)}\n`);
  return catalog;
}

async function fetchGitHubReleases({ repository, token }) {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "lattice-release-notes",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const releases = [];
  for (let page = 1; page <= 10; page += 1) {
    const response = await fetch(
      `https://api.github.com/repos/${repository}/releases?per_page=100&page=${page}`,
      { headers },
    );

    if (!response.ok) {
      console.warn(`warning: could not fetch GitHub releases (${response.status} ${response.statusText})`);
      return releases;
    }

    const pageReleases = await response.json();
    if (!Array.isArray(pageReleases) || pageReleases.length === 0) {
      return releases;
    }

    releases.push(...pageReleases);
    if (pageReleases.length < 100) {
      return releases;
    }
  }

  return releases;
}

export function parseReleaseSections(body) {
  const sections = [];
  let currentSection;

  for (const rawLine of body.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }

    const sectionMatch = line.match(/^#{3,6}\s+(.+)$/);
    if (sectionMatch) {
      currentSection = {
        title: cleanInlineMarkdown(sectionMatch[1]),
        items: [],
      };
      sections.push(currentSection);
      continue;
    }

    if (/^#{1,2}\s+/.test(line)) {
      continue;
    }

    const itemMatch = line.match(/^(?:[-*]|\d+\.)\s+(.+)$/);
    if (itemMatch) {
      if (!currentSection) {
        currentSection = {
          title: "Changes",
          items: [],
        };
        sections.push(currentSection);
      }

      currentSection.items.push(parseReleaseItem(itemMatch[1]));
    }
  }

  return sections.filter((section) => section.items.length > 0);
}

function parseReleaseItem(markdown) {
  const linkMatch = markdown.match(/\[[^\]]+\]\((https?:\/\/[^)]+)\)/);
  return {
    text: cleanInlineMarkdown(markdown),
    url: linkMatch ? linkMatch[1] : null,
  };
}

function cleanInlineMarkdown(markdown) {
  return markdown
    .replace(/\[([^\]]+)\]\((?:https?:\/\/[^)]+)\)/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/__([^_]+)__/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeVersion(tagName, releaseName) {
  const candidate = releaseName && releaseName !== "Latest" ? releaseName : tagName;
  return candidate.replace(/^v/, "");
}

function releaseURL(repository, tagName) {
  return `https://github.com/${repository}/releases/tag/${encodeURIComponent(tagName)}`;
}

function compareEntries(a, b) {
  const dateComparison = Date.parse(b.publishedAt || "") - Date.parse(a.publishedAt || "");
  if (!Number.isNaN(dateComparison) && dateComparison !== 0) {
    return dateComparison;
  }
  return b.tagName.localeCompare(a.tagName, undefined, { numeric: true, sensitivity: "base" });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await writeReleaseNotesCatalog();
}
