#!/usr/bin/env bash
#
# run-stage.sh — run ONE audit prompt through fresh-context, web-enabled Claude
# Code children, and emit structured JSON (tool calls + sources) per run.
#
# This is the workhorse the AX-audit skill calls once per stage. Each run is an
# isolated `claude -p` child with NO personal settings/skills/MCP (clean context)
# but WITH WebSearch + WebFetch, so it researches like a real developer.
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
#   --runs N                 Max runs for this stage (default 5; cheap workflow uses 1-3).
#   --out DIR                Output directory for this stage (created if needed).
#   --stage NAME             Stage label recorded in the output (default: derived from --prompt).
#   --company-domains LIST   Comma-separated domains for the audited company. Any
#                            WebFetch to / search hit on these hosts is flagged as
#                            "sourced from the company's own material".
#   --model MODEL            Child-run model alias/full ID (default: haiku). Use "default"
#                            to let Claude Code choose.
#   --effort LEVEL           Optional effort level (low, medium, high, xhigh, max).
#   --max-budget-usd AMOUNT  Per-run Claude Code budget cap (print mode).
#   --max-turns N            Optional per-run agentic turn cap. Off by default.
#   --max-web-searches N     Optional per-run WebSearch cap, enforced by PreToolUse hook.
#   --max-web-fetches N      Optional per-run WebFetch cap, enforced by PreToolUse hook.
#   --max-web-total N        Optional per-run combined WebSearch+WebFetch cap.
#   --stop-on-mention-regex REGEX
#                            After each successful run, stop the stage early if answer
#                            matches REGEX (case-insensitive). Intended for Discovery.
#
# Output (in DIR):
#   run-01.raw.jsonl ... run-NN.raw.jsonl   full event stream per run
#   run-01.json      ... run-NN.json        parsed compact record per run
#   run-01.web-cap.json                    optional web-cap counter state
#   stage.json                              { stage, prompt, run_policy, runs:[...] }
#
# Parsed run record fields:
#   run, session_id, model, num_turns, total_cost_usd, is_error,
#   answer                 final assistant text
#   tool_calls: [ { name, input, hit_company_domain } ]   (ToolSearch plumbing filtered out)
#   fetched_urls: [...]    every WebFetch url
#   search_queries: [...]  every WebSearch query
#   result_sources: [...]  hosts/links seen in tool_result content (best-effort)
#   company_domain_hits: [...]  the subset of the above matching --company-domains
#
# Notes:
#   * No Anthropic API key needed — uses Claude subscription OAuth.
#   * Subscription rate limits apply; keep budgets and web caps on for sampling runs.
#   * Each child runs in its own mktemp dir so it can't read your project files.

set -euo pipefail

PROMPT_PATH=""; RUNS=5; OUT=""; STAGE=""; COMPANY_DOMAINS=""
MODEL="haiku"; EFFORT=""; MAX_BUDGET_USD=""; MAX_TURNS=""
MAX_WEB_SEARCHES=""; MAX_WEB_FETCHES=""; MAX_WEB_TOTAL=""
STOP_ON_MENTION_REGEX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt|--prompt-file) PROMPT_PATH="${2:-}"; shift 2 ;;
    --runs)                 RUNS="${2:-}"; shift 2 ;;
    --out)                  OUT="${2:-}"; shift 2 ;;
    --stage)                STAGE="${2:-}"; shift 2 ;;
    --company-domains)      COMPANY_DOMAINS="${2:-}"; shift 2 ;;
    --model)                MODEL="${2:-}"; shift 2 ;;
    --effort)               EFFORT="${2:-}"; shift 2 ;;
    --max-budget-usd)       MAX_BUDGET_USD="${2:-}"; shift 2 ;;
    --max-turns)            MAX_TURNS="${2:-}"; shift 2 ;;
    --max-web-searches)     MAX_WEB_SEARCHES="${2:-}"; shift 2 ;;
    --max-web-fetches)      MAX_WEB_FETCHES="${2:-}"; shift 2 ;;
    --max-web-total)        MAX_WEB_TOTAL="${2:-}"; shift 2 ;;
    --stop-on-mention-regex) STOP_ON_MENTION_REGEX="${2:-}"; shift 2 ;;
    -h|--help)              sed -n '1,/^set -euo pipefail/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -e "$PROMPT_PATH" ]] || { echo "Error: --prompt path not found: $PROMPT_PATH" >&2; exit 2; }
[[ -n "$OUT" ]]        || { echo "Error: --out required" >&2; exit 2; }
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 1 ]] || { echo "Error: --runs must be a positive integer" >&2; exit 2; }
[[ -z "$MAX_TURNS" || "$MAX_TURNS" =~ ^[0-9]+$ ]] || { echo "Error: --max-turns must be an integer" >&2; exit 2; }
[[ -z "$MAX_WEB_SEARCHES" || "$MAX_WEB_SEARCHES" =~ ^[0-9]+$ ]] || { echo "Error: --max-web-searches must be an integer" >&2; exit 2; }
[[ -z "$MAX_WEB_FETCHES" || "$MAX_WEB_FETCHES" =~ ^[0-9]+$ ]] || { echo "Error: --max-web-fetches must be an integer" >&2; exit 2; }
[[ -z "$MAX_WEB_TOTAL" || "$MAX_WEB_TOTAL" =~ ^[0-9]+$ ]] || { echo "Error: --max-web-total must be an integer" >&2; exit 2; }
[[ -z "$MAX_BUDGET_USD" || "$MAX_BUDGET_USD" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "Error: --max-budget-usd must be a number" >&2; exit 2; }
command -v claude  >/dev/null || { echo "Error: 'claude' not on PATH." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Error: 'python3' not on PATH." >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP_HOOK="$SCRIPT_DIR/web-cap-hook.py"

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
# --strict-mcp-config drops MCP servers; --tools restricts the built-in tool list;
# --allowedTools lets the web tools run without interactive prompts.
CLEAN_FLAGS=(--setting-sources "" --strict-mcp-config
             --tools "WebSearch,WebFetch"
             --allowedTools "WebSearch" "WebFetch"
             --output-format stream-json --verbose
             --no-session-persistence)

if [[ -n "$MODEL" && "$MODEL" != "default" ]]; then
  CLEAN_FLAGS+=(--model "$MODEL")
fi
if [[ -n "$EFFORT" && "$EFFORT" != "default" ]]; then
  CLEAN_FLAGS+=(--effort "$EFFORT")
fi
if [[ -n "$MAX_BUDGET_USD" ]]; then
  CLEAN_FLAGS+=(--max-budget-usd "$MAX_BUDGET_USD")
fi
if [[ -n "$MAX_TURNS" ]]; then
  CLEAN_FLAGS+=(--max-turns "$MAX_TURNS")
fi

caps_enabled=0
if [[ -n "$MAX_WEB_SEARCHES" || -n "$MAX_WEB_FETCHES" || -n "$MAX_WEB_TOTAL" ]]; then
  caps_enabled=1
  [[ -x "$CAP_HOOK" ]] || { echo "Error: web cap hook missing or not executable: $CAP_HOOK" >&2; exit 1; }
fi

pool_n=${#POOL_FILES[@]}
model_label="$MODEL"
[[ -z "$model_label" || "$model_label" == "default" ]] && model_label="Claude Code default"
cap_label=""
[[ -n "$MAX_BUDGET_USD" ]] && cap_label+=" budget=\$$MAX_BUDGET_USD"
[[ -n "$MAX_WEB_SEARCHES" ]] && cap_label+=" searches=$MAX_WEB_SEARCHES"
[[ -n "$MAX_WEB_FETCHES" ]] && cap_label+=" fetches=$MAX_WEB_FETCHES"
[[ -n "$MAX_WEB_TOTAL" ]] && cap_label+=" web_total=$MAX_WEB_TOTAL"
if [[ $pool_n -gt 1 ]]; then
  echo "Stage '$STAGE': up to $RUNS run(s) cycling a pool of $pool_n prompt(s), model=$model_label, web-enabled,$cap_label out=$OUT"
else
  echo "Stage '$STAGE': up to $RUNS run(s), model=$model_label, web-enabled,$cap_label out=$OUT"
fi

STOPPED_EARLY=0
STOP_REASON=""

for n in $(seq 1 "$RUNS"); do
  nn="$(printf '%02d' "$n")"
  raw="$OUT/run-$nn.raw.jsonl"
  rec="$OUT/run-$nn.json"
  web_state="$OUT/run-$nn.web-cap.json"
  # cycle through the pool: run n uses pool file (n-1) mod pool_n
  pf="${POOL_FILES[$(( (n-1) % pool_n ))]}"
  prompt="$(cat "$pf")"
  if [[ $pool_n -gt 1 ]]; then
    echo "  [$n/$RUNS] running (prompt: $(basename "$pf"))..."
  else
    echo "  [$n/$RUNS] running..."
  fi
  workdir="$(mktemp -d)"
  RUN_FLAGS=("${CLEAN_FLAGS[@]}")
  ENV_ARGS=(env -i HOME="$HOME" PATH="$PATH")

  if [[ $caps_enabled -eq 1 ]]; then
    settings="$workdir/ax-web-cap-settings.json"
    python3 - "$settings" "$CAP_HOOK" <<'PY'
import json, sys
path, hook = sys.argv[1:3]
settings = {
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "WebSearch|WebFetch",
                "hooks": [{"type": "command", "command": hook}],
            }
        ]
    }
}
open(path, "w", encoding="utf-8").write(json.dumps(settings, indent=2))
PY
    RUN_FLAGS+=(--settings "$settings")
    ENV_ARGS+=(
      AX_WEB_CAP_FILE="$web_state"
      AX_MAX_WEB_SEARCHES="$MAX_WEB_SEARCHES"
      AX_MAX_WEB_FETCHES="$MAX_WEB_FETCHES"
      AX_MAX_WEB_TOTAL="$MAX_WEB_TOTAL"
    )
  fi

  # stream-json requires -p; --verbose streams every event to stdout as JSONL.
  ( cd "$workdir" && "${ENV_ARGS[@]}" \
      claude -p "$prompt" "${RUN_FLAGS[@]}" ) > "$raw" 2>"$raw.err" || true
  rm -rf "$workdir"

  python3 "$SCRIPT_DIR/parse-run.py" \
    --raw "$raw" --out "$rec" --run "$n" \
    --prompt-file "$pf" \
    --company-domains "$COMPANY_DOMAINS" || {
      echo "    ! parse failed for run $n (see $raw.err)"; }

  if [[ -n "$STOP_ON_MENTION_REGEX" ]]; then
    if python3 - "$rec" "$STOP_ON_MENTION_REGEX" <<'PY'
import json, re, sys
rec_path, pattern = sys.argv[1:3]
r = json.load(open(rec_path, encoding="utf-8"))
if r.get("is_error"):
    sys.exit(1)
answer = r.get("answer") or ""
sys.exit(0 if re.search(pattern, answer, re.I | re.M) else 1)
PY
    then
      STOPPED_EARLY=1
      STOP_REASON="Stop-on-mention regex matched after run $n."
      echo "    -> $STOP_REASON"
      break
    fi
  fi
done

# Assemble the stage record from the per-run records.
# Pool files are passed as argv after the fixed metadata args (stdin is the heredoc).
python3 - "$OUT" "$STAGE" "$COMPANY_DOMAINS" "$RUNS" "$MODEL" "$EFFORT" \
  "$MAX_BUDGET_USD" "$MAX_TURNS" "$MAX_WEB_SEARCHES" "$MAX_WEB_FETCHES" "$MAX_WEB_TOTAL" \
  "$STOPPED_EARLY" "$STOP_REASON" "$STOP_ON_MENTION_REGEX" "${POOL_FILES[@]}" <<'PY'
import json, glob, os, sys

(
    out, stage, domains, requested_runs, model, effort, max_budget, max_turns,
    max_searches, max_fetches, max_total, stopped_early, stop_reason,
    mention_regex, *pool
) = sys.argv[1:]

runs = []
for f in sorted(glob.glob(os.path.join(out, "run-*.json"))):
    try:
        runs.append(json.load(open(f, encoding="utf-8")))
    except Exception:
        pass

prompts = [{"file": os.path.basename(p), "text": open(p, encoding="utf-8").read()} for p in pool if p.strip()]

def maybe_num(value):
    if value == "":
        return None
    try:
        return int(value)
    except ValueError:
        try:
            return float(value)
        except ValueError:
            return value

caps = {
    "max_budget_usd": maybe_num(max_budget),
    "max_turns": maybe_num(max_turns),
    "max_web_searches": maybe_num(max_searches),
    "max_web_fetches": maybe_num(max_fetches),
    "max_web_total": maybe_num(max_total),
}
caps = {k: v for k, v in caps.items() if v is not None}

run_policy = {
    "requested_runs": int(requested_runs),
    "actual_runs": len(runs),
    "prompt_pool_size": len(prompts),
    "runner_model": None if model in ("", "default") else model,
    "effort": None if effort in ("", "default") else effort,
    "caps": caps,
    "stopped_early": stopped_early == "1",
    "stop_reason": stop_reason or None,
    "stop_on_mention_regex": mention_regex or None,
}

rec = {
    "stage": stage,
    "prompt_pool": prompts,                         # all prompts used (1 = repeated; >1 = cycled)
    "prompt": prompts[0]["text"] if prompts else "", # representative prompt for the report
    "company_domains": [d.strip() for d in domains.split(",") if d.strip()],
    "run_policy": run_policy,
    "runs": runs,
}
json.dump(rec, open(os.path.join(out, "stage.json"), "w", encoding="utf-8"), indent=2)
kind = f"pool of {len(prompts)}" if len(prompts) > 1 else "single prompt"
early = " (stopped early)" if run_policy["stopped_early"] else ""
print(f"  -> {len(runs)} run(s) recorded ({kind}){early} in {os.path.join(out,'stage.json')}")
PY
