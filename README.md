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

## Super mini tutorial

Use this skill when you want to know how a fresh AI coding agent sees a company.

1. Install the skill into `~/.claude/skills/`.
2. In Claude Code, ask: `Run an AX audit on <company/domain>`.
3. Claude researches the company, confirms the category/use case/competitors, and writes
   realistic prompts for the four audit stages.
4. The runner executes a small budgeted sample of fresh Claude Code child sessions: Discovery
   runs adaptively (1-3 runs), while Recommendation / Comparison / Agent Tooling run once each.
5. The runner records each child's real `stream-json` output: answer, web searches, fetched
   URLs, model, cost, and errors.
6. The judgement pass scores each run/stage with the AX rubric and writes `audit.json`.
7. Open `audits/<slug>/report.html` beside `audit.json`, or inline the data into one
   self-contained HTML file.

The default workflow is intentionally small so you can sample AX visibility without burning
through a Claude session limit. Ask for a deeper audit only when you are ready to spend more
usage.

## Claude spawning mini tutorial

The audit does **not** use Claude subagents for the measurement runs. It starts new Claude
Code CLI processes with `claude -p "<prompt>"`, one process per run, from a temporary working
directory.

The important runner flags are:

- `--setting-sources ""` — do not load user/project/local settings for the child run.
- `--strict-mcp-config` with no `--mcp-config` — ignore configured MCP servers, so project or
  user MCP tools do not leak into the test.
- `--tools "WebSearch,WebFetch"` — restrict built-in tools to web search/fetch.
- `--allowedTools "WebSearch" "WebFetch"` — let those web tools run without interactive
  permission prompts. This is permission control, not the restriction mechanism.
- `--output-format stream-json --verbose` — capture every tool call and result as JSONL.
- `--model haiku`, `--max-budget-usd ...`, and the `web-cap-hook.py` PreToolUse hook — keep
  child research runs cheaper and bounded.

How this differs from Claude subagents:

- Subagents are delegated assistants inside a Claude Code session. They have their own
  context window, prompt, tools, and permissions, and are great for codebase tasks that
  should return a summary to the main conversation.
- AX measurement needs a stricter product-test environment: no inherited chat history, no
  project context, no skills, no MCP servers, and only web tools. Separate `claude -p` child
  sessions make that isolation explicit and repeatable.
- Subagents are optimized for context management. This runner is optimized for measurement:
  it keeps raw JSONL audit trails for every run, so the report can prove which searches and
  fetches happened.

See the official [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference)
and [Claude subagents docs](https://code.claude.com/docs/en/sub-agents) for the underlying
flags and subagent behavior.

## Repo layout

The installable skill is the source of truth. The repo keeps examples at the root, but the
runner, prompts, rubric, schema, and report renderer all live inside the folder you copy into
Claude Code.

```
.claude/skills/ax-audit/SKILL.md        # the skill workflow
.claude/skills/ax-audit/scripts/        # runner, parser, prompt guard, web-cap hook
.claude/skills/ax-audit/prompts/        # four stage intent specs
.claude/skills/ax-audit/report/         # report renderer, schema, rubric
examples/release-report-inline.html     # example single-file output with inline data
```

## Requirements

- [Claude Code](https://claude.com/claude-code) on your PATH, authenticated (subscription is fine)
- `python3`
- A POSIX shell (bash)

## Credit

Scoring rubric and stage design adapted from Ritza's
["How to Do an AX Audit"](https://techstackups.com/articles/how-to-do-an-ax-audit/).
