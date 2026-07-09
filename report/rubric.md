# AX scoring rubric (1–4)

Adapted from Ritza's AX-audit framework
(techstackups.com/articles/how-to-do-an-ax-audit). Every stage and run is scored on
the same four-point band:

| Score | Band | Meaning |
|-------|------|---------|
| 4 | **GOOD** | Working as expected; no significant friction |
| 3 | **OK**   | Mostly works; minor gaps |
| 2 | **POOR** | Partial; significant friction or gaps |
| 1 | **FAIL** | Broken or absent |

The overall score rounds from the stage scores (round to nearest; note the raw mean
in the summary, e.g. "rounded up from 2.75").

Below, each stage gets a concrete reading of what each band looks like. The
enrichment pass scores each **run** against the stage's ladder, then gives the stage
a holistic score.

---

## Stage 1 — Discovery
*Can an agent find you when a developer asks an open, generic question?*

| Score | What it looks like |
|-------|--------------------|
| 4 GOOD | Top choice for several generic prompts |
| 3 OK   | Top-3 recommendation for several generic prompts |
| 2 POOR | Mentioned only when the prompt is narrowed toward the product's niche |
| 1 FAIL | Never appears unless named directly |

Signals: does `answer` mention the company? Where in the list? Do any `tool_calls`
have `hit_company_domain: true`, or is `company_domain_hits` empty?

## Stage 2 — Recommendation
*Given a real use case, does the agent actually recommend you?*

| Score | What it looks like |
|-------|--------------------|
| 4 GOOD | Recommended as the top pick for the use case |
| 3 OK   | In the top 3, with a fair description |
| 2 POOR | Mentioned as an also-ran / alternative, not a real recommendation |
| 1 FAIL | Not recommended even for its ideal use case |

Signals: `recommended` field (`top` / `top3` / `listed` / `no`); is the reasoning
accurate and fair, or dismissive?

## Stage 3 — Comparison
*When compared head-to-head with competitors, is the agent's account correct?*

| Score | What it looks like |
|-------|--------------------|
| 4 GOOD | Accurate, fair, specific; concrete numbers check out |
| 3 OK   | Broadly right; minor stale or vague points |
| 2 POOR | Notable gaps or an unfair framing |
| 1 FAIL | Confidently wrong on material facts (worse than absence) |

Signals: cross-check concrete claims (pricing, limits) against
`company_domain_hits`/`fetched_urls`. A confident-but-wrong claim is a 1 even if the
company is mentioned a lot — flag it explicitly in `why`.

## Stage 4 — Agent Tooling Availability
*Does the agent find agent-native tooling (llms.txt, md docs, OpenAPI, MCP, skills)?*

| Score | What it looks like |
|-------|--------------------|
| 4 GOOD | MCP + llms.txt + agent skills, all discoverable and useful |
| 3 OK   | MCP server and/or skills exist; some coverage gaps |
| 2 POOR | API accessible but underdocumented; no MCP server |
| 1 FAIL | No structured agent tooling of any kind found |

Signals: did the agent find real tooling URLs (check `fetched_urls` /
`company_domain_hits` for `/llms.txt`, `*.md`, `mcp`, `openapi`)? Did it have to be
told to look, or find them unprompted?
