---
name: ax-audit
description: Run an Agent Experience (AX) audit on a company. Drives fresh-context, web-enabled Claude Code instances through Discovery / Recommendation / Comparison / Agent-Tooling prompts, scores each response 1–4 against the AX rubric, and produces a self-contained HTML report. Use when someone asks "how do AI agents see my product?", wants an AX audit / AX scorecard, or wants to test whether Claude Code discovers and recommends their platform.
---

# AX Audit

You run an **Agent Experience audit**: you measure what a fresh, web-enabled Claude Code
instance says about a company when a developer asks the kinds of questions that lead to
a tool choice. You run a set of prompts many times, capture the real tool calls and
sources, score each response 1–4 on the AX rubric, and render an HTML report.

The company being audited usually scores *badly* — that's the point. The report shows
them exactly where agents fail to find, recommend, or correctly describe their product.

## What you produce

A folder `audits/<company-slug>/` containing:
- `stages/<stage>/` — raw runs (`run-NN.raw.jsonl`), parsed records, `stage.json`
- `audit.json` — the enriched dataset (schema: `report/schema.md`)
- `report.html` — the self-contained report (copy of `report/report.html`)
- Open `report.html` next to `audit.json` (or inline the data — see step 5).

## The four stages

From Ritza's AX framework. Each is one prompt, run N times:

1. **Discovery** — open question ("what {{category}} should I use?"). Does the company appear at all?
2. **Recommendation** — a real use case. Is the company recommended, or an also-ran?
3. **Comparison** — head-to-head vs named competitors. Is the agent's account *correct*?
4. **Agent Tooling Availability** — does the agent find the company's llms.txt / md docs / OpenAPI / MCP / skills?

Scoring is 1–4 (FAIL / POOR / OK / GOOD). Full ladders per stage: `report/rubric.md`.
**Read `report/rubric.md` and `report/schema.md` before enriching — do not invent fields or bands.**

---

## Steps — follow in order

### 1. Gather inputs (ask the user)

You need, and must confirm with the user before running anything:

- **Company name** and **domain(s)** (e.g. Release, `release.com`, `docs.release.com`).
  Domains drive the "sourced from the company's own docs" flag — get them right.
- **Category** — the product class a developer would search for ("deployment platform").
- **A concrete use case** — for the Recommendation and Comparison prompts.
- **Competitors** — 2–4 named rivals for the Comparison prompt.
- **Runs per stage** — **ask the user; default 5.** More runs = better variance signal but
  more cost/rate-limit pressure. (Session note: subscription rate limits apply.)

If the user just says "audit my company", ask these questions before proceeding. Do not
guess the domain or competitors.

### 2. Fill the prompt templates

Copy `prompts/*.txt` into `audits/<slug>/prompts/` and replace the placeholders
(`{{CATEGORY}}`, `{{USECASE}}`, `{{COMPANY}}`, `{{DOMAIN}}`, `{{COMPETITORS}}`) with the
gathered values. Keep the "list every URL you consulted under a Sources heading" line —
it's the self-report cross-check for sources.

### 3. Run each stage (the runner)

For each of the four prompts, call the runner. It runs the prompt N times as clean-context,
**web-enabled** children and writes structured records:

```bash
scripts/run-stage.sh \
  --prompt-file audits/<slug>/prompts/01-discovery.txt \
  --runs <N> \
  --out audits/<slug>/stages/discovery \
  --stage discovery \
  --company-domains "release.com,docs.release.com"
```

Repeat for `02-recommendation`, `03-comparison`, `04-agent-tooling`.

- No API key needed (subscription OAuth). Each run costs ~$0.10–0.30 equivalent.
- The runner uses `--output-format stream-json --verbose`, so tool calls and sources are
  captured for real — you do **not** have to rely on the agent's self-reported sources
  (though the prompt asks for them too, as a cross-check).
- Pace large batches; if you hit rate limits, lower `--runs` and re-run the missing stage.

### 4. Enrich each run (this is your judgement pass)

After a stage finishes, read its `stage.json`. For **each run**, read `answer` +
`tool_calls` + `company_domain_hits`, then add these fields to the run object
(per `report/schema.md`):

- `score` (1–4) and `band`, judged against that stage's ladder in `report/rubric.md`.
- `mentioned` (bool) — did the answer name the company at all?
- `recommended` — `"no" | "listed" | "top3" | "top"`.
- `why` — 1–3 sentences citing the evidence (position in the list, whether
  `company_domain_hits` is empty, any wrong claim). **Reference the observed data**, don't
  hand-wave. A confident-but-wrong claim in Comparison is a 1 even if the company is
  mentioned — say so.

Then score the **stage**: a holistic 1–4 (usually near the mean of its run scores; weight
down for confident-wrong answers). Write `stage.score`, `stage.band`, `stage.summary`,
plus `stage.title`, `stage.intent`, `stage.prompt`.

### 5. Assemble `audit.json` and drop in the report

Build `audits/<slug>/audit.json` matching `report/schema.md`: top-level `company`,
`domains`, `category`, `competitors`, `generated_at`, `runs_per_stage`, `mode`
(`"web-enabled"`), the four enriched `stages`, and finally the `overall` object
(score = rounded mean of stage scores; summary = the headline finding).

Copy the report next to it:

```bash
cp report/report.html audits/<slug>/report.html
```

The report auto-loads `audit.json` from the same folder when served over HTTP. For a
**single-file, double-clickable** report, inline the data instead: prepend
`<script>window.AUDIT_DATA = <contents of audit.json>;</script>` into `report.html`
before the main `<script>` (the report checks `window.AUDIT_DATA` first).

### 6. Hand off

Tell the user where the report is and how to open it (double-click the single-file
version, or `python3 -m http.server` in the folder for the fetch version). Lead with the
overall score and the single most important finding (usually: the company is absent from
Discovery/Recommendation despite web access).

---

## Guardrails

- **Always web-enabled** in this version — the runner grants WebSearch + WebFetch. There is
  no model-knowledge-only mode here.
- **Don't fabricate runs or scores.** Every run in `audit.json` must come from a real
  `run-NN.json`. Every score must trace to the rubric and the observed answer.
- **Report is a dumb renderer** — it never computes scores. If a number is wrong, fix it in
  `audit.json`, not in the HTML.
- **Keep the raw `.raw.jsonl` files** — they're the audit trail proving the tool calls and
  sources are real, not summarised by you.
