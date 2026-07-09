#!/usr/bin/env python3
"""PreToolUse hook that caps WebSearch/WebFetch calls per Claude Code run."""

import json
import os
import sys


def read_int_env(name):
    raw = os.environ.get(name, "").strip()
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def deny(reason):
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        return 0

    tool = event.get("tool_name")
    if tool not in {"WebSearch", "WebFetch"}:
        return 0

    state_path = os.environ.get("AX_WEB_CAP_FILE")
    if not state_path:
        return 0

    max_searches = read_int_env("AX_MAX_WEB_SEARCHES")
    max_fetches = read_int_env("AX_MAX_WEB_FETCHES")
    max_total = read_int_env("AX_MAX_WEB_TOTAL")

    try:
        with open(state_path, encoding="utf-8") as fh:
            state = json.load(fh)
    except Exception:
        state = {"WebSearch": 0, "WebFetch": 0}

    searches = int(state.get("WebSearch") or 0)
    fetches = int(state.get("WebFetch") or 0)
    total = searches + fetches

    if max_total is not None and total >= max_total:
        deny(f"AX audit web cap reached: total WebSearch/WebFetch limit is {max_total}.")
        return 0

    if tool == "WebSearch" and max_searches is not None and searches >= max_searches:
        deny(f"AX audit web cap reached: WebSearch limit is {max_searches}.")
        return 0

    if tool == "WebFetch" and max_fetches is not None and fetches >= max_fetches:
        deny(f"AX audit web cap reached: WebFetch limit is {max_fetches}.")
        return 0

    state[tool] = int(state.get(tool) or 0) + 1
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2, sort_keys=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
