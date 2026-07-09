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
#   ./run-stage.sh --prompt PATH --runs N --out DIR [--stage NAME] [--company-domains "a.com,b.io"]
#
#   --prompt PATH            A prompt file OR a directory of prompt files.
#                              * single file  -> that prompt is repeated N times
#                                                (Recommendation / Comparison / Agent-Tooling).
#                              * directory     -> the *.txt files in it form a POOL; the N runs
#                                                cycle through the pool in sorted order, so
#                                                phrasing variance is sampled too (Discovery).
#                            (--prompt-file is accepted as an alias for a single file.)
#   --runs N                 How many runs for this stage (variance sampling).
#   --out DIR                Output directory for this stage (created if needed).
#   --stage NAME             Stage label recorded in the output (default: derived from --prompt).
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

PROMPT_PATH=""; RUNS=5; OUT=""; STAGE=""; COMPANY_DOMAINS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt|--prompt-file) PROMPT_PATH="${2:-}"; shift 2 ;;
    --runs)             RUNS="${2:-}"; shift 2 ;;
    --out)              OUT="${2:-}"; shift 2 ;;
    --stage)            STAGE="${2:-}"; shift 2 ;;
    --company-domains)  COMPANY_DOMAINS="${2:-}"; shift 2 ;;
    -h|--help)          grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -e "$PROMPT_PATH" ]] || { echo "Error: --prompt path not found: $PROMPT_PATH" >&2; exit 2; }
[[ -n "$OUT" ]]        || { echo "Error: --out required" >&2; exit 2; }
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 1 ]] || { echo "Error: --runs must be a positive integer" >&2; exit 2; }
command -v claude  >/dev/null || { echo "Error: 'claude' not on PATH." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Error: 'python3' not on PATH." >&2; exit 1; }

# Build the prompt POOL: one entry per file (single file -> pool of 1).
declare -a POOL_FILES=()
if [[ -d "$PROMPT_PATH" ]]; then
  shopt -s nullglob
  POOL_FILES=("$PROMPT_PATH"/*.txt)
  shopt -u nullglob
  IFS=$'\n' POOL_FILES=($(sort <<<"${POOL_FILES[*]}")); unset IFS
  [[ ${#POOL_FILES[@]} -gt 0 ]] || { echo "Error: no *.txt files in pool dir: $PROMPT_PATH" >&2; exit 2; }
  [[ -z "$STAGE" ]] && STAGE="$(basename "$PROMPT_PATH")"
else
  POOL_FILES=("$PROMPT_PATH")
  [[ -z "$STAGE" ]] && STAGE="$(basename "${PROMPT_PATH%.txt}")"
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# Clean context + web enabled. --setting-sources "" drops CLAUDE.md/skills/hooks;
# --strict-mcp-config drops MCP servers; --allowedTools grants exactly the web tools.
CLEAN_FLAGS=(--setting-sources "" --strict-mcp-config
             --allowedTools "WebSearch" "WebFetch"
             --output-format stream-json --verbose)

pool_n=${#POOL_FILES[@]}
if [[ $pool_n -gt 1 ]]; then
  echo "Stage '$STAGE': $RUNS run(s) cycling a pool of $pool_n prompt(s), web-enabled, out=$OUT"
else
  echo "Stage '$STAGE': $RUNS run(s), web-enabled, out=$OUT"
fi

for n in $(seq 1 "$RUNS"); do
  nn="$(printf '%02d' "$n")"
  raw="$OUT/run-$nn.raw.jsonl"
  rec="$OUT/run-$nn.json"
  # cycle through the pool: run n uses pool file (n-1) mod pool_n
  pf="${POOL_FILES[$(( (n-1) % pool_n ))]}"
  prompt="$(cat "$pf")"
  if [[ $pool_n -gt 1 ]]; then
    echo "  [$n/$RUNS] running (prompt: $(basename "$pf"))..."
  else
    echo "  [$n/$RUNS] running..."
  fi
  workdir="$(mktemp -d)"
  # stream-json requires -p; --verbose streams every event to stdout as JSONL.
  ( cd "$workdir" && env -i HOME="$HOME" PATH="$PATH" \
      claude -p "$prompt" "${CLEAN_FLAGS[@]}" ) > "$raw" 2>"$raw.err" || true
  rm -rf "$workdir"

  python3 "$(dirname "$0")/parse-run.py" \
    --raw "$raw" --out "$rec" --run "$n" \
    --prompt-file "$pf" \
    --company-domains "$COMPANY_DOMAINS" || {
      echo "    ! parse failed for run $n (see $raw.err)"; }
done

# Assemble the stage record from the per-run records.
# Pool files are passed as argv after the fixed three args (stdin is the heredoc).
python3 - "$OUT" "$STAGE" "$COMPANY_DOMAINS" "${POOL_FILES[@]}" <<'PY'
import json, glob, os, sys
out, stage, domains = sys.argv[1:4]
pool = [p for p in sys.argv[4:] if p.strip()]
runs = []
for f in sorted(glob.glob(os.path.join(out, "run-*.json"))):
    try: runs.append(json.load(open(f)))
    except Exception: pass
prompts = [{"file": os.path.basename(p), "text": open(p).read()} for p in pool]
rec = {
    "stage": stage,
    "prompt_pool": prompts,                 # all prompts used (1 = repeated; >1 = cycled)
    "prompt": prompts[0]["text"] if prompts else "",   # representative prompt for the report
    "company_domains": [d.strip() for d in domains.split(",") if d.strip()],
    "runs": runs,
}
json.dump(rec, open(os.path.join(out, "stage.json"), "w"), indent=2)
kind = f"pool of {len(prompts)}" if len(prompts) > 1 else "single prompt"
print(f"  -> {len(runs)} run(s) recorded ({kind}) in {os.path.join(out,'stage.json')}")
PY
