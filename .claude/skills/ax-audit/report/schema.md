# AX audit data schema

The skill produces one `audit.json` that the HTML report reads. It is built in two
passes:

1. **Runner pass** (`scripts/run-stage.sh` + `parse-run.py`) fills the *observed*
   fields — the raw facts of each run (answer, tool calls, sources).
2. **Enrichment pass** (the orchestrating Claude, guided by `SKILL.md`) adds the
   *judged* fields — scores, summaries, and the company-mention flag — by reading
   each run's answer and tool calls against the rubric in `rubric.md`.

The report never computes scores; it only renders what the enrichment pass wrote.

## Top-level `audit.json`

```jsonc
{
  "company": "Release",
  "domains": ["release.com", "docs.release.com"],
  "category": "deployment platform",
  "competitors": ["Vercel", "Railway", "Render", "Fly.io"],
  "generated_at": "2026-07-08T16:40:00Z",
  "runs_per_stage": 5,
  "mode": "web-enabled",              // this version always web-enabled

  "overall": {                        // written by enrichment pass, last
    "score": 2,                       // 1-4, rounded from the stage scores
    "band": "POOR",                   // FAIL | POOR | OK | GOOD (see rubric.md)
    "summary": "Release is absent from generic and constrained deployment-platform
                queries; the agent only reaches release.com when the company is named
                directly. Strong docs once found, but discoverability is the gap."
  },

  "stages": [ /* one Stage object per stage, in order */ ]
}
```

## Stage object

```jsonc
{
  "id": "discovery",
  "title": "Discovery",
  "intent": "Can an agent find you when a developer asks an open question?",
  "prompt": "I'm a developer choosing a deployment platform. What are the top options...",

  "score": 1,                         // 1-4, enrichment pass
  "band": "FAIL",
  "summary": "Release did not appear in any of the 5 runs. The agent consistently
              recommends Vercel, Railway, Render, Fly.io and cites third-party
              comparison articles — never release.com.",

  "runs": [ /* one Run object per run */ ]
}
```

## Run object

Observed fields come from `parse-run.py`; judged fields are added by enrichment.

```jsonc
{
  // --- observed (runner) ---
  "run": 1,
  "session_id": "cdfa8df3-...",
  "num_turns": 4,
  "total_cost_usd": 0.245,
  "is_error": false,
  "answer": "Here's a rundown of the main options...",     // full agent answer
  "tool_calls": [
    { "name": "WebSearch", "input": {"query": "best deployment platforms 2026"},
      "hit_company_domain": false },
    { "name": "WebFetch",  "input": {"url": "https://release.com"},
      "hit_company_domain": true }                          // <- highlighted in report
  ],
  "fetched_urls": ["https://release.com"],
  "search_queries": ["best deployment platforms 2026"],
  "result_sources": ["https://www.digitalocean.com/...", "..."],
  "company_domain_hits": ["https://release.com"],           // empty = company not sourced

  // --- judged (enrichment pass) ---
  "score": 1,                         // 1-4 for THIS run, per rubric.md
  "band": "FAIL",
  "mentioned": false,                 // did the answer mention the company at all?
  "recommended": "no",                // "no" | "listed" | "top3" | "top" 
  "why": "Lists Vercel, Railway, Render, Fly.io and Heroku; Release never appears.
          Sources are third-party comparison blogs. company_domain_hits is empty."
}
```

## Field notes

- **`hit_company_domain`** on a tool call is the "it sourced the company's own material"
  flag the report highlights. It's set by the runner (host match against `domains`),
  so it's an *observed* fact, not a judgement.
- **`mentioned` / `recommended`** are quick booleans/enums the enrichment pass fills so
  the report can show per-run chips without re-reading the prose.
- **`band`** is always derivable from `score` (1=FAIL, 2=POOR, 3=OK, 4=GOOD) but is
  stored explicitly so the report stays a dumb renderer.
- A stage `score` is the enrichment pass's holistic 1-4 for the stage — usually near
  the mean of its run scores, but the pass may weight (e.g. one confident-but-wrong
  answer drags a Comparison stage down more than the mean suggests).
