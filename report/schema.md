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
  "runs_per_stage": {                 // may be a number for older reports
    "discovery": "1-3 adaptive",
    "recommendation": 1,
    "comparison": 1,
    "agent_tooling": 1
  },
  "mode": "web-enabled",              // child runs are always web-enabled
  "run_policy_summary": "Discovery: 1-3 adaptive; Recommendation/Comparison/Agent Tooling: 1 each",
  "run_policy": {
    "runner_model": "haiku",
    "judge_model": "opus",
    "caps": {
      "max_budget_usd": 1.25,
      "max_web_searches": 8,
      "max_web_fetches": 8,
      "max_web_total": 12
    }
  },

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
  "prompt": "I'm building a full-stack app and need somewhere to host it...",  // representative
  "prompt_pool": [                    // Discovery cycles a pool; other stages have 1 entry
    { "file": "01-host.txt",     "text": "..." },
    { "file": "02-previews.txt", "text": "..." },
    { "file": "03-owncloud.txt", "text": "..." }
  ],

  "score": 1,                         // 1-4, enrichment pass; null if skipped
  "band": "FAIL",
  "skipped": false,
  "summary": "Release did not appear in any of the 5 runs. The agent consistently
              recommends Vercel, Railway, Render, Fly.io and cites third-party
              comparison articles — never release.com.",
  "run_policy": {
    "requested_runs": 3,
    "actual_runs": 1,
    "prompt_pool_size": 3,
    "runner_model": "haiku",
    "caps": {
      "max_budget_usd": 1.25,
      "max_web_searches": 8,
      "max_web_fetches": 8,
      "max_web_total": 12
    },
    "stopped_early": true,
    "stop_reason": "Stop-on-mention regex matched after run 1.",
    "stop_on_mention_regex": "\\bCompanyName\\b"
  },

  "runs": [ /* one Run object per run */ ]
}
```

**Pooled vs. repeated prompts.** Discovery cycles a **pool** of several generic phrasings
across its runs (each run records the exact `prompt` it used — see the Run object). The other
three stages repeat a single prompt, so their `prompt_pool` has one entry. The report shows
each run's own `prompt` so the reader sees which phrasing produced which answer.

**Variable run counts are normal.** The budgeted default runs Discovery adaptively
(minimum 1, maximum 3) and the other stages once each. `run_policy.requested_runs` is the
maximum asked for; `actual_runs` is what happened after early stopping, errors, or user
skipping. Older reports may still use a numeric top-level `runs_per_stage`.

**Skipped stages stay explicit.** If the user skips a stage, include a Stage object with
`skipped: true`, `score: null`, a short `summary`, and an empty `runs` array. This keeps the
report honest about scope without pretending missing work was completed.

## Run object

Observed fields come from `parse-run.py`; judged fields are added by enrichment.

```jsonc
{
  // --- observed (runner) ---
  "run": 1,
  "prompt": "I'm building a full-stack app and need somewhere to host it...",  // this run's exact prompt
  "session_id": "cdfa8df3-...",
  "model": "claude-haiku-4-5-20251001",
  "model_usage": {
    "claude-haiku-4-5-20251001": {
      "inputTokens": 12345,
      "outputTokens": 2345,
      "webSearchRequests": 4,
      "costUSD": 0.08
    }
  },
  "num_turns": 4,
  "total_cost_usd": 0.245,
  "is_error": false,
  "terminal_reason": "completed",
  "permission_denials": [],
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
- **`model` / `model_usage` / `terminal_reason` / `permission_denials`** come from Claude
  Code's result stream. They make rate limits, budget caps, tool denials, and accidental
  model drift visible in the audit trail.
- **`run_policy.caps`** records the intended guardrails. The runner enforces web caps through
  a `PreToolUse` hook and budget caps through Claude Code's `--max-budget-usd`.
