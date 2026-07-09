#!/usr/bin/env bash
#
# check-prompts.sh — guard against company/competitor names leaking into the
# Discovery and Recommendation prompts, which would invalidate their scores.
#
# A Discovery/Recommendation "mention" only counts if the agent surfaced the
# company UNPROMPTED. If the prompt itself names the company (or a competitor,
# which primes the answer), the stage measures nothing. This script greps the
# given prompt files and exits non-zero if a forbidden name appears, so the
# skill can refuse to run a leaking prompt.
#
# Usage:
#   check-prompts.sh --company "NAME" [--domains "a.com,b.io"] \
#                    [--competitors "Vercel,Railway"] \
#                    --discovery FILE --recommendation FILE
#
# Case-insensitive, whole-word-ish matching. Domains are matched as substrings
# (release.com matches docs.release.com references too). Competitors are optional
# but recommended — priming by a rival name is also a leak.

set -euo pipefail

COMPANY=""; DOMAINS=""; COMPETITORS=""; DISCOVERY=""; RECOMMENDATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --company)        COMPANY="${2:-}"; shift 2 ;;
    --domains)        DOMAINS="${2:-}"; shift 2 ;;
    --competitors)    COMPETITORS="${2:-}"; shift 2 ;;
    --discovery)      DISCOVERY="${2:-}"; shift 2 ;;
    --recommendation) RECOMMENDATION="${2:-}"; shift 2 ;;
    -h|--help)        grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$COMPANY" ]] || { echo "Error: --company required" >&2; exit 2; }

# Build the forbidden-term list: company name, its domains, and competitors.
declare -a TERMS=()
[[ -n "$COMPANY" ]] && TERMS+=("$COMPANY")
IFS=',' read -ra _d <<< "$DOMAINS";     for t in "${_d[@]}"; do [[ -n "${t// }" ]] && TERMS+=("${t// }"); done
IFS=',' read -ra _c <<< "$COMPETITORS"; for t in "${_c[@]}"; do [[ -n "${t// }" ]] && TERMS+=("${t// }"); done

fail=0
check_file() {
  local label="$1" file="$2"
  [[ -n "$file" ]] || return 0
  [[ -f "$file" ]] || { echo "  ! $label: file not found: $file" >&2; fail=1; return; }
  local hit=0
  for term in "${TERMS[@]}"; do
    # -i case-insensitive, -w word boundary for names; domains contain dots so -w
    # won't apply cleanly — fall back to plain -i substring for anything with a dot.
    if [[ "$term" == *.* ]]; then
      grep -iqF -- "$term" "$file" && { echo "  ✗ $label leaks '$term'"; hit=1; }
    else
      grep -iqw -- "$term" "$file" && { echo "  ✗ $label leaks '$term'"; hit=1; }
    fi
  done
  if [[ $hit -eq 0 ]]; then echo "  ✓ $label clean"; else fail=1; fi
}

echo "Leak check (company='$COMPANY'):"
check_file "discovery" "$DISCOVERY"
check_file "recommendation" "$RECOMMENDATION"

if [[ $fail -ne 0 ]]; then
  echo "" >&2
  echo "FAIL: a forbidden name appears in a Discovery/Recommendation prompt." >&2
  echo "Rewrite the prompt to remove it — these stages must stay company-agnostic." >&2
  exit 1
fi
echo "OK: Discovery & Recommendation prompts are company-agnostic."
