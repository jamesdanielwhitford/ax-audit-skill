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
MCP — but **with web search + fetch**) through four stages using a budgeted default sample:
Discovery runs adaptively (minimum 1, maximum 3), while the remaining stages run once each.

| Stage | Question |
|-------|----------|
| **Discovery** | Does the agent mention you when asked an open question about your category? |
| **Recommendation** | Given a real use case, does it recommend you — or an incumbent? |
| **Comparison** | Head-to-head with competitors, is its account of you *correct*? |
| **Agent Tooling** | Does it find your `llms.txt` / markdown docs / OpenAPI / MCP / skills? |

Every response is scored **1–4** (FAIL / POOR / OK / GOOD) on the
[Ritza AX rubric](https://techstackups.com/articles/how-to-do-an-ax-audit/), with a
Markdown-rendered "why", key reasons, and concrete suggestions. The report highlights any
tool call that sourced *your own* documentation.

The result is a self-contained **HTML report** — an overall score, a tab per stage with
Markdown-rendered summaries, key reasons, suggestions, score-colored run tabs, and per-run
detail. Each run shows **Why This Score** before a chat-style transcript with the user prompt
and agent response bubbles, followed by tool calls and sources. Agent answers can include
headings, lists, code, links, and Markdown tables.

## How the data is captured

The runner uses `claude -p --output-format stream-json --verbose`, so it records the real
tool calls — the exact `WebSearch` queries and `WebFetch` URLs — not just counts. The
prompts also ask the agent to list its sources, as a cross-check. No Anthropic API key is
needed; it runs on your Claude subscription (OAuth), so mind your subscription rate limits.

By default, child research runs use `--model haiku` plus per-run budget and web-call caps.
Discovery can stop early when a safe company-mention regex matches a completed run. Final
scoring/judgement should be done with an Opus-class model reading the captured artifacts.

## Install

Copy the skill into your Claude Code skills directory:

```bash
git clone https://github.com/jamesdanielwhitford/ax-audit-skill
cp -r ax-audit-skill/.claude/skills/ax-audit ~/.claude/skills/
```

Then in Claude Code: **"Run an AX audit on my company"** — the skill will confirm your
domain, category, use case, and competitors, then use the budgeted default workflow unless
you explicitly ask for a deeper audit.

## Repo layout

```
scripts/run-stage.sh    # runs prompts as budgeted web-enabled clean-context children
scripts/parse-run.py    # distils a run's stream into tool calls + sources
scripts/web-cap-hook.py # optional PreToolUse hook enforcing WebSearch/WebFetch caps
scripts/check-prompts.sh# guards against company/competitor names leaking into
                        #   the Discovery/Recommendation prompts (would void the score)
prompts/*.md            # the four stage INTENT SPECS (target + guardrails + examples);
                        #   the orchestrator writes company-specific prompts from these
report/report.html      # self-contained Markdown/chat-style report renderer
report/schema.md        # the audit.json data model, including key_reasons/suggestions
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
