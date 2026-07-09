# Stage 4 — Agent Tooling Availability

**Target of this stage:** Does the agent discover the company's *agent-native* tooling — the
things a company ships specifically to help agents use it: `llms.txt`, markdown versions of
docs, an OpenAPI spec, an MCP server, installable skills? And do those actually help?

## What the generated prompt must do
- **Name the company and its domain** (correct and required here).
- Frame it as a developer wanting to use the company *with an AI coding agent*, asking what
  agent-native tooling exists — each item with a URL and a note on whether it helps.
- Instruct the agent to research the domain and its docs directly.
- End with the "list every URL you consulted under a Sources heading" line.

## Hard guardrails
- Use the real domain(s) from the research (drives the `hit_company_domain` flag).
- Ask about the specific artifact types (llms.txt, .md docs, OpenAPI, MCP, skills) so a thin
  answer is visible as a gap, not hidden behind vagueness.

## Example prompts (across verticals — for tone/scope)
- *(deployment)* "I want to use Release (release.com) with an AI coding agent. What agent-native tooling do they provide — llms.txt, markdown docs, an OpenAPI spec, an MCP server, installable skills? Give the URL for each and say whether it actually helps an agent get started."
- *(any)* "Does <Company> (<domain>) offer anything specifically for AI agents — an llms.txt, machine-readable docs, an MCP server, or agent skills? For each, where is it and is it useful?"

## Signals for scoring (see report/rubric.md)
Check `fetched_urls` / `company_domain_hits` for `/llms.txt`, `*.md`, `mcp`, `openapi`. Did
the agent have to be told to look, or find them? 4 = MCP + llms.txt + skills, discoverable &
useful · 3 = MCP and/or skills, some gaps · 2 = API but underdocumented, no MCP · 1 = no
agent tooling found.
