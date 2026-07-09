---
name: ax-audit
description: Run an Agent Experience (AX) audit on a company. Researches the company, generates realistic developer prompts, drives fresh-context web-enabled Claude Code instances through Discovery / Recommendation / Comparison / Agent-Tooling, scores each response 1–4 against the AX rubric, and produces a self-contained HTML report. Use when someone asks "how do AI agents see my product?", wants an AX audit / AX scorecard, or wants to test whether Claude Code discovers and recommends their platform.
---

# AX Audit

You run an **Agent Experience audit**: you measure what a fresh, web-enabled Claude Code
instance says about a company when a developer asks the kinds of questions that lead to a
tool choice. You research the company, generate realistic prompts, run a small budgeted
sample of fresh child agents, capture the real tool calls and sources, score each response
1–4, and render an HTML report.

The company being audited usually scores *badly* — that's the point. The report shows them
exactly where agents fail to find, recommend, or correctly describe their product.

## Core principle: intent, not templates

The four stages are defined by **intent + guardrails + examples**, held in `prompts/*.md` —
NOT by fixed prompt strings. You **research the company and write company-specific prompts**
that fit its category and audience. The examples in `prompts/*.md` exist to anchor tone,
scope, and the exact target of each stage — read them, match their register, don't copy them.

## What you produce

A folder `audits/<company-slug>/` containing:
- `prompts/NN-stage.txt` — the concrete prompts you generated for THIS company
- `stages/<stage>/` — raw runs (`run-NN.raw.jsonl`), parsed records, `stage.json`
- `audit.json` — the enriched dataset (schema: `report/schema.md`)
- `report.html` — the self-contained report

## The four stages

1. **Discovery** — open question; does the company appear unprompted? (`prompts/01-discovery.md`)
2. **Recommendation** — real use case; is the company recommended? (`prompts/02-recommendation.md`)
3. **Comparison** — head-to-head vs competitors; is the account correct? (`prompts/03-comparison.md`)
4. **Agent Tooling** — does the agent find llms.txt / md docs / OpenAPI / MCP / skills? (`prompts/04-agent-tooling.md`)

Scoring is 1–4 (FAIL / POOR / OK / GOOD): `report/rubric.md`.
**Read `report/rubric.md`, `report/schema.md`, and all four `prompts/*.md` before starting.**

---

## Steps — follow in order

### 1. Research the company (you browse; use WebSearch/WebFetch freely)

You are the orchestrator — browsing here is *setup*, not the test, so research freely. From
the company's domain(s), establish:

- **What the product is** and its **category** (the product class a developer would search for).
- **Ideal use case(s)** — what it's genuinely good for (drives the Recommendation prompt).
- **Real competitors** — 2–4 named rivals (drives the Comparison prompt).
- **Existing agent tooling** — check for `/llms.txt`, markdown docs, OpenAPI, MCP, skills.

Ask the user only for what you can't determine or must confirm: the exact domain(s) if
ambiguous. Use the budgeted default run policy unless the user explicitly asks for a deeper
audit:

- Discovery: adaptive, **minimum 1 / maximum 3** runs. Stop early if the company appears
  credibly in a completed run.
- Recommendation: **1** run.
- Comparison: **1** run.
- Agent Tooling: **1** run, unless the user skips it.

Confirm your understanding of the company in one short line ("You're X, a <category>; ideal
for <use case>; competitors <A/B/C>") — a single confirmation, then proceed. Do not stop for
prompt-by-prompt approval.

### 2. Generate the prompts (per stage, from the research)

Follow each stage's `prompts/NN-*.md` spec — its target, guardrails, and example register.

- **Discovery uses a POOL.** Write several (≈3) different generic phrasings to a *directory*
  `audits/<slug>/prompts/discovery/*.txt` — e.g. a broad "where do I host this?", a
  previews-angle one, a deploy-to-own-cloud one. The runs cycle through them, so you sample
  phrasing variance (generic → narrowing toward the niche), never naming a product.
- **Recommendation / Comparison / Agent-Tooling use a SINGLE prompt** each, written to
  `audits/<slug>/prompts/NN-stage.txt` and repeated across runs.

**Leak guardrail (critical, non-negotiable):**
- **Discovery and Recommendation prompts must NOT contain the company name or any competitor
  name.** A mention only counts if unprompted. After writing them, verify with:
  ```bash
  scripts/check-prompts.sh --company "Release" --domains "release.com" \
    --discovery audits/<slug>/prompts/01-discovery.txt \
    --recommendation audits/<slug>/prompts/02-recommendation.txt
  ```
  If it errors, rewrite the offending prompt to remove the name. Do not run a leaking prompt.
- **Comparison and Agent-Tooling prompts SHOULD name the company** (and, for Comparison, the
  competitors) — that's correct there.

Every prompt ends with: *"list every URL you consulted under a Sources heading."*

### 3. Run each stage (the runner)

For each stage, run its prompt(s) as clean-context, **web-enabled** children. Child research
runs should use **Haiku** by default; reserve Opus-level judgement for the enrichment pass.
Point `--prompt` at the Discovery *directory* (pool) or at a single-file prompt for the
others:

```bash
# Discovery — pass the pool DIRECTORY; runs cycle through the phrasings.
# Use a safe mention regex. For ambiguous company names, require product/domain context,
# not just the bare word.
scripts/run-stage.sh \
  --prompt audits/<slug>/prompts/discovery \
  --runs 3 --out audits/<slug>/stages/discovery \
  --stage discovery --company-domains "release.com,docs.release.com" \
  --model haiku \
  --max-budget-usd 1.25 --max-web-searches 8 --max-web-fetches 8 --max-web-total 12 \
  --stop-on-mention-regex '<safe-company-mention-regex>'

# Recommendation / Comparison / Agent-Tooling — single prompt file, repeated
scripts/run-stage.sh \
  --prompt audits/<slug>/prompts/02-recommendation.txt \
  --runs 1 --out audits/<slug>/stages/recommendation \
  --stage recommendation --company-domains "release.com,docs.release.com" \
  --model haiku \
  --max-budget-usd 1.25 --max-web-searches 8 --max-web-fetches 8 --max-web-total 12
```

Repeat for `03-comparison`, `04-agent-tooling`. For Comparison, use a slightly higher budget
only when the prompt asks for current pricing/limits across several vendors (for example,
`--max-budget-usd 2 --max-web-searches 12 --max-web-fetches 12 --max-web-total 18`).

- No API key needed (subscription OAuth). Subscription usage limits still apply.
- Runner uses `--output-format stream-json --verbose`, so tool calls and sources are captured
  for real — you don't rely on the agent's self-reported sources (the prompt asks for them
  too, as a cross-check).
- Do not run unbudgeted batches by default. If a run hits a budget/web cap, keep the error
  record, score the stage honestly, and only rerun with higher caps if the user agrees.

### 4. Enrich each run (your judgement pass)

Read each completed stage's `stage.json`. Use Opus-level judgement for this pass; if the
current Claude Code session is not running an Opus-class model, pause and ask the user to
continue the enrichment/report step with Opus. For **each run**, read `answer` +
`tool_calls` + `company_domain_hits`, then add to the run object (per `report/schema.md`):

- `score` (1–4) and `band`, judged against that stage's ladder in `report/rubric.md`.
- `mentioned` (bool); `recommended` (`"no" | "listed" | "top3" | "top"`).
- `why` — 1–3 sentences citing the evidence (position in list, empty `company_domain_hits`,
  any wrong claim). A confident-but-wrong Comparison claim is a 1 even if mentioned — say so.

Then score the **stage** holistically (near the mean of run scores; weight down confident-wrong
answers). Write `stage.score/band/summary/title/intent/prompt`.

### 5. Assemble `audit.json` and drop in the report

Build `audits/<slug>/audit.json` matching `report/schema.md` (top-level `company`, `domains`,
`category`, `competitors`, `generated_at`, `runs_per_stage` as an object, `run_policy`,
`mode: "web-enabled"`, the enriched or explicitly skipped `stages`, then `overall`: score =
rounded mean of non-skipped stage scores; summary = the headline finding). Copy the report
next to it:

```bash
cp report/report.html audits/<slug>/report.html
```

The report auto-loads `audit.json` from the same folder over HTTP. For a single-file,
double-clickable report, inline the data: prepend
`<script>window.AUDIT_DATA = <contents of audit.json>;</script>` before the main `<script>`.

### 6. Hand off

Tell the user where the report is and how to open it. Lead with the overall score and the
single most important finding (usually: the company is absent from Discovery/Recommendation
despite web access).

---

## Guardrails

- **Always web-enabled** — the runner grants WebSearch + WebFetch. No model-knowledge-only mode.
- **Budgeted by default** — child research runs use Haiku and must include per-run budget and
  web-call caps unless the user explicitly requests a deeper audit.
- **No company/competitor names in Discovery or Recommendation prompts** — enforced by
  `scripts/check-prompts.sh`. This protects score validity; never skip it.
- **Discovery early stop must be credible** — pass `--stop-on-mention-regex`, but do not use
  a bare ambiguous company name like "Release" if it can match ordinary prose. Require product,
  domain, or category context in the regex.
- **Don't fabricate runs or scores.** Every run in `audit.json` comes from a real
  `run-NN.json`; every score traces to the rubric and the observed answer.
- **Report is a dumb renderer** — never computes scores. Fix numbers in `audit.json`, not the HTML.
- **Keep the raw `.raw.jsonl` files** — they're the audit trail proving the tool calls are real.
