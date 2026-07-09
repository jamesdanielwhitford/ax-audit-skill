# Stage 3 — Comparison

**Target of this stage:** When the company is put head-to-head against named competitors, is
the agent's account of the company **correct**? A confident-but-wrong claim is worse than
absence — it actively misleads a developer evaluating the company.

## What the generated prompt must do
- **Name the company and the confirmed competitors** (this is the one stage where naming the
  company is correct and required).
- Ask for a specific comparison: pricing, key features, limitations — with concrete numbers
  where possible, for a stated use case.
- Instruct the agent to research current details rather than rely on memory (so we can check
  whether it fetched the company's own docs).
- End with the "list every URL you consulted under a Sources heading" line.

## Hard guardrails
- Use the real competitor names from the research/user confirmation, not invented ones.
- Anchor to a concrete use case so "it depends" answers still have to commit to specifics.

## Example prompts (across verticals — for tone/scope)
- *(deployment)* "How does Release compare to Vercel, Railway, and Render for deploying a full-stack app with per-PR preview environments? Cover pricing, key features, and limitations, with concrete numbers."
- *(observability)* "Compare Honeycomb, Datadog, and Grafana Cloud for tracing a Kubernetes microservices app — pricing tiers, data retention, and any notable limitations."
- *(voice AI)* "Compare ElevenLabs and the OpenAI Realtime API for a streaming voice agent: latency, language support, per-minute pricing, and limitations."

## Signals for scoring (see report/rubric.md)
Cross-check concrete claims against `company_domain_hits` / `fetched_urls`. 4 = accurate,
fair, specific · 3 = broadly right, minor stale/vague points · 2 = notable gaps or unfair
framing · 1 = confidently wrong on a material fact (flag it explicitly in `why`).
