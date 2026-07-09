#!/usr/bin/env python3
"""
parse-run.py — distil one Claude Code stream-json run into a compact record.

The runner writes each child's full event stream to run-NN.raw.jsonl
(`--output-format stream-json --verbose`). This script reads that stream and
extracts exactly the fields the AX-audit report needs:

  - the final assistant answer text
  - every tool call (name + input), with ToolSearch plumbing filtered out
  - WebFetch URLs and WebSearch queries, separated
  - sources/links surfaced in tool_result content (best-effort)
  - which of those hit the audited company's own domain(s)
  - the result envelope's model / cost / turns / session_id / error flag

Usage:
  parse-run.py --raw run-01.raw.jsonl --out run-01.json --run 1 \
               --company-domains "release.com,docs.release.com"
"""
import argparse, json, re
from urllib.parse import urlparse


def host_of(url: str) -> str:
    try:
        h = urlparse(url).netloc.lower()
        return h[4:] if h.startswith("www.") else h
    except Exception:
        return ""


def domain_match(host: str, domains) -> bool:
    """True if host equals or is a subdomain of any target domain."""
    host = host.lower()
    for d in domains:
        d = d.lower().lstrip(".")
        if host == d or host.endswith("." + d):
            return True
    return False


def iter_events(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


URL_RE = re.compile(r'https?://[^\s"\'<>)\]}]+')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--run", type=int, required=True)
    ap.add_argument("--prompt-file", default="")
    ap.add_argument("--company-domains", default="")
    args = ap.parse_args()

    domains = [d.strip() for d in args.company_domains.split(",") if d.strip()]

    prompt_text = ""
    if args.prompt_file:
        try:
            prompt_text = open(args.prompt_file, encoding="utf-8", errors="replace").read()
        except OSError:
            pass

    rec = {
        "run": args.run,
        "prompt": prompt_text,          # the exact prompt this run used (matters for pools)
        "session_id": None,
        "model": None,
        "model_usage": {},
        "num_turns": None,
        "total_cost_usd": None,
        "is_error": None,
        "terminal_reason": None,
        "permission_denials": [],
        "answer": "",
        "tool_calls": [],
        "fetched_urls": [],
        "search_queries": [],
        "result_sources": [],
        "company_domain_hits": [],
    }

    last_assistant_text = ""

    for ev in iter_events(args.raw):
        et = ev.get("type")

        if et == "assistant":
            model = ev.get("message", {}).get("model")
            if model and not rec["model"]:
                rec["model"] = model
            for c in ev.get("message", {}).get("content", []):
                if c.get("type") == "text" and c.get("text", "").strip():
                    last_assistant_text = c["text"]
                elif c.get("type") == "tool_use":
                    name = c.get("name", "")
                    inp = c.get("input", {}) or {}
                    # ToolSearch is plumbing (the child loading deferred web tools).
                    if name == "ToolSearch":
                        continue
                    url = inp.get("url", "")
                    hit = bool(url) and domain_match(host_of(url), domains)
                    rec["tool_calls"].append(
                        {"name": name, "input": inp, "hit_company_domain": hit}
                    )
                    if name == "WebFetch" and url:
                        rec["fetched_urls"].append(url)
                        if hit and url not in rec["company_domain_hits"]:
                            rec["company_domain_hits"].append(url)
                    elif name == "WebSearch" and inp.get("query"):
                        rec["search_queries"].append(inp["query"])

        elif et == "user":
            # tool_result content — scrape any URLs the search/fetch returned.
            for c in ev.get("message", {}).get("content", []):
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    body = c.get("content", "")
                    text = body if isinstance(body, str) else json.dumps(body)
                    for url in URL_RE.findall(text):
                        url = url.rstrip(".,);")
                        if url not in rec["result_sources"]:
                            rec["result_sources"].append(url)
                        if domain_match(host_of(url), domains) and url not in rec["company_domain_hits"]:
                            rec["company_domain_hits"].append(url)

        elif et == "result":
            rec["session_id"] = ev.get("session_id")
            rec["num_turns"] = ev.get("num_turns")
            rec["total_cost_usd"] = ev.get("total_cost_usd")
            rec["is_error"] = ev.get("is_error")
            rec["model_usage"] = ev.get("modelUsage") or {}
            rec["terminal_reason"] = ev.get("terminal_reason")
            rec["permission_denials"] = ev.get("permission_denials") or []
            if isinstance(ev.get("result"), str) and ev["result"].strip():
                last_assistant_text = ev["result"]

    rec["answer"] = last_assistant_text
    # cap result_sources to keep the record compact
    rec["result_sources"] = rec["result_sources"][:40]

    json.dump(rec, open(args.out, "w"), indent=2)


if __name__ == "__main__":
    main()
