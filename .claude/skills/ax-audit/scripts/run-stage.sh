#!/usr/bin/env bash
#
# run-stage.sh — run ONE audit prompt N times through fresh-context, web-enabled
# Claude Code children, and emit structured JSON (tool calls + sources) per run.
#
# This is the workhorse the AX-audit skill calls once per stage. Each run is an
# isolated `claude -p` child with NO personal settings/skills/MCP (clean context)
# but WITH WebSearch + WebFetch granted, so it researches like a real developer.
#
# We use --output-format stream-json --verbose (not plain json) because the plain
# json envelope only reports tool-use *counts*; the stream gives every tool_use
# block (the exact WebSearch queries and WebFetch URLs) and every tool_result.
# A Python parser distils each run's raw JSONL into a compact run record.
#
# Usage:
#   ./run-stage.sh --prompt-file FILE --runs N --out DIR [--stage NAME] [--company-domains "a.com,b.io"]
#
#   --prompt-file FILE       Path to the prompt text file for this stage.
#   --runs N                 How many times to run the prompt (variance sampling).
#   --out DIR                Output directory for this stage (created if needed).
#   --stage NAME             Stage label recorded in the output (default: prompt filename).
#   --company-domains LIST   Comma-separated domains for the audited company. Any
#                            WebFetch to / search hit on these hosts is flagged as
#                            "sourced from the company's own material".
#
# Output (in DIR):
#   run-01.raw.jsonl ... run-NN.raw.jsonl   full event stream per run
#   run-01.json      ... run-NN.json        parsed compact record per run
#   stage.json                              { stage, prompt, company_domains, runs:[...] }
#
# Parsed run record fields:
#   run, session_id, num_turns, total_cost_usd, is_error,
#   answer                 final assistant text
#   tool_calls: [ { name, input, hit_company_domain } ]   (ToolSearch plumbing filtered out)
#   fetched_urls: [...]    every WebFetch url
#   search_queries: [...]  every WebSearch query
#   result_sources: [...]  hosts/links seen in tool_result content (best-effort)
#   company_domain_hits: [...]  the subset of the above matching --company-domains
#
# Notes:
#   * No Anthropic API key needed — uses Claude subscription OAuth.
#   * Subscription rate limits apply; pace large batches.
#   * Each child runs in its own mktemp dir so it can't read your project files.

set -euo pipefail

PROMPT_FILE=""; RUNS=5; OUT=""; STAGE=""; COMPANY_DOMAINS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file)      PROMPT_FILE="${2:-}"; shift 2 ;;
    --runs)             RUNS="${2:-}"; shift 2 ;;
    --out)              OUT="${2:-}"; shift 2 ;;
    --stage)            STAGE="${2:-}"; shift 2 ;;
    --company-domains)  COMPANY_DOMAINS="${2:-}"; shift 2 ;;
    -h|--help)          grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$PROMPT_FILE" ]] || { echo "Error: --prompt-file not found: $PROMPT_FILE" >&2; exit 2; }
[[ -n "$OUT" ]]        || { echo "Error: --out required" >&2; exit 2; }
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 1 ]] || { echo "Error: --runs must be a positive integer" >&2; exit 2; }
command -v claude  >/dev/null || { echo "Error: 'claude' not on PATH." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Error: 'python3' not on PATH." >&2; exit 1; }

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
[[ -z "$STAGE" ]] && STAGE="$(basename "${PROMPT_FILE%.txt}")"
PROMPT="$(cat "$PROMPT_FILE")"

# Clean context + web enabled. --setting-sources "" drops CLAUDE.md/skills/hooks;
# --strict-mcp-config drops MCP servers; --allowedTools grants exactly the web tools.
CLEAN_FLAGS=(--setting-sources "" --strict-mcp-config
             --allowedTools "WebSearch" "WebFetch"
             --output-format stream-json --verbose)

echo "Stage '$STAGE': $RUNS run(s), web-enabled, out=$OUT"

for n in $(seq 1 "$RUNS"); do
  nn="$(printf '%02d' "$n")"
  raw="$OUT/run-$nn.raw.jsonl"
  rec="$OUT/run-$nn.json"
  echo "  [$n/$RUNS] running..."
  workdir="$(mktemp -d)"
  # stream-json requires -p; --verbose streams every event to stdout as JSONL.
  ( cd "$workdir" && env -i HOME="$HOME" PATH="$PATH" \
      claude -p "$PROMPT" "${CLEAN_FLAGS[@]}" ) > "$raw" 2>"$raw.err" || true
  rm -rf "$workdir"

  python3 "$(dirname "$0")/parse-run.py" \
    --raw "$raw" --out "$rec" --run "$n" \
    --company-domains "$COMPANY_DOMAINS" || {
      echo "    ! parse failed for run $n (see $raw.err)"; }
done

# Assemble the stage record from the per-run records.
python3 - "$OUT" "$STAGE" "$PROMPT_FILE" "$COMPANY_DOMAINS" <<'PY'
import json, glob, os, sys
out, stage, prompt_file, domains = sys.argv[1:5]
runs = []
for f in sorted(glob.glob(os.path.join(out, "run-*.json"))):
    try: runs.append(json.load(open(f)))
    except Exception: pass
rec = {
    "stage": stage,
    "prompt_file": os.path.basename(prompt_file),
    "prompt": open(prompt_file).read(),
    "company_domains": [d.strip() for d in domains.split(",") if d.strip()],
    "runs": runs,
}
json.dump(rec, open(os.path.join(out, "stage.json"), "w"), indent=2)
print(f"  -> {len(runs)} run(s) recorded in {os.path.join(out,'stage.json')}")
PY
