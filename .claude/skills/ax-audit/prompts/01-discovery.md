# Stage 1 — Discovery

**Target of this stage:** Does the agent surface the company *unprompted*, when a developer
who doesn't yet know the product exists asks a generic question about the problem space?

## This stage uses a POOL
Discovery generates **several (≈3) different generic phrasings**, written as separate `.txt`
files in a `discovery/` directory. The runs cycle through them, so you sample phrasing
variance (a broad question, a previews-angle question, a deploy-to-own-cloud question…),
moving generic → narrowing toward the company's niche — but no phrasing may name a product.

## What each generated prompt must do
- Sound like a real developer in the company's target audience asking an **open** question
  about their category or problem — *before* they know any specific product.
- Ask for recommendations / options, so the agent has to name products.
- End with: "list every URL you consulted under a Sources heading" (source cross-check).

## Hard guardrails
- **Never name the company.** A Discovery mention only counts if it was unprompted.
- **Never name a competitor either** — that primes the answer. Keep it about the *problem*.
- Keep it generic first; if you generate several, you may narrow toward the company's niche
  across them (generic → constrained), but none may name a product.

## Example prompts (across verticals — for tone/scope, not to copy verbatim)
- *(deployment)* "I'm building a full-stack web app and need somewhere to host it. What are the top options I should consider?"
- *(observability)* "What do teams use these days to monitor and trace a production microservices backend?"
- *(voice AI)* "I want to add realtime voice conversations to my app. What are the best APIs for that right now?"
- *(database)* "I need a managed Postgres-compatible database for a new SaaS. What should I look at?"
- *(browser automation)* "What's the best way to run headless browsers at scale for scraping and testing?"

## Signals for scoring (see report/rubric.md)
Does the company appear in `answer`? Where in the list? Is `company_domain_hits` empty?
4 = top pick across prompts · 3 = top-3 · 2 = only when narrowed to its niche · 1 = never.
