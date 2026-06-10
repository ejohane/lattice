import agents from "../skills/AGENTS.md" with { type: "text" };
import answerFromWiki from "../skills/answer-from-wiki.md" with { type: "text" };
import ingestCaptures from "../skills/ingest-captures.md" with { type: "text" };
import lintWiki from "../skills/lint-wiki.md" with { type: "text" };
import maintainWiki from "../skills/maintain-wiki.md" with { type: "text" };

export const bundledSkillTemplates = [
  {
    relativePath: "AGENTS.md",
    content: agents,
  },
  {
    relativePath: "answer-from-wiki.md",
    content: answerFromWiki,
  },
  {
    relativePath: "ingest-captures.md",
    content: ingestCaptures,
  },
  {
    relativePath: "lint-wiki.md",
    content: lintWiki,
  },
  {
    relativePath: "maintain-wiki.md",
    content: maintainWiki,
  },
] as const;
