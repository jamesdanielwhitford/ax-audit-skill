# AX Audit Skill

A [Claude Code](https://claude.com/claude-code) skill that runs an **Agent Experience (AX)
audit** on any company: it measures what a fresh, web-enabled Claude Code instance actually
says about your product when a developer asks the questions that lead to a tool choice.

If AI coding agents can't find, recommend, or correctly describe your platform, you're
invisible to a fast-growing slice of the developer market. This skill quantifies that.

## What it does

First it **researches your company** (what it is, its category, its real competitors, its
ideal use case, and any existing agent tooling) and confirms that understanding with you.
Then it **writes realistic developer prompts** tailored to your product — the skill holds the
*intent* of each stage, not fixed templates, so it works for a deployment platform, an
observability tool, a voice API, or a database equally well.

Then it drives isolated, clean-context Claude Code children (no personal settings, skills, or
MCP — but **with web search + fetch**) through four stages, each run several times:

| Stage | Question |
|-------|----------|
| **Discovery** | Does the agent mention you when asked an open question about your category? |
| **Recommendation** | Given a real use case, does it recommend you — or an incumbent? |
| **Comparison** | Head-to-head with competitors, is its account of you *correct*? |
| **Agent Tooling** | Does it find your `llms.txt` / markdown docs / OpenAPI / MCP / skills? |

Every response is scored **1–4** (FAIL / POOR / OK / GOOD) on the
[Ritza AX rubric](https://techstackups.com/articles/how-to-do-an-ax-audit/), with a
"why", and the report highlights any tool call that sourced *your own* documentation.

The result is a self-contained **HTML report** — an overall score, a tab per stage with its
score and summary, and per-run detail showing the exact prompt, the agent's answer, every
tool call it made, and the sources it fetched.

## How the data is captured

The runner uses `claude -p --output-format stream-json --verbose`, so it records the real
tool calls — the exact `WebSearch` queries and `WebFetch` URLs — not just counts. The
prompts also ask the agent to list its sources, as a cross-check. No Anthropic API key is
needed; it runs on your Claude subscription (OAuth), so mind your subscription rate limits
on big batches.

## Install

Copy the skill into your Claude Code skills directory:

```bash
git clone https://github.com/jamesdanielwhitford/ax-audit-skill
cp -r ax-audit-skill/.claude/skills/ax-audit ~/.claude/skills/
```

Then in Claude Code: **"Run an AX audit on my company"** — the skill will ask for your
domain, category, a use case, competitors, and how many runs per stage (default 5).

## Repo layout

```
scripts/run-stage.sh    # runs one prompt N times, web-enabled, clean context
scripts/parse-run.py    # distils a run's stream into tool calls + sources
scripts/check-prompts.sh# guards against company/competitor names leaking into
                        #   the Discovery/Recommendation prompts (would void the score)
prompts/*.md            # the four stage INTENT SPECS (target + guardrails + examples);
                        #   the orchestrator writes company-specific prompts from these
report/report.html      # self-contained report renderer (reads audit.json)
report/schema.md        # the audit.json data model
report/rubric.md        # the 1–4 scoring ladders per stage
.claude/skills/ax-audit/SKILL.md   # the skill itself (drives the whole workflow)
```

## Requirements

- [Claude Code](https://claude.com/claude-code) on your PATH, authenticated (subscription is fine)
- `python3`
- A POSIX shell (bash)

## Credit

Scoring rubric and stage design adapted from Ritza's
["How to Do an AX Audit"](https://techstackups.com/articles/how-to-do-an-ax-audit/).
