# Stage 2 — Recommendation

**Target of this stage:** Given a *real, specific use case* in the company's category, does
the agent actually recommend the company — as a top pick, an also-ran, or not at all?

## What the generated prompt must do
- Describe a concrete, realistic project/use case that the company is genuinely good for
  (drawn from the research — their ideal use case), phrased as a developer asking for a
  recommendation.
- Ask "which specific product would you recommend, and why?" — force a named pick, ideally
  a ranked top few.
- End with the "list every URL you consulted under a Sources heading" line.

## Hard guardrails
- **Never name the company.** The point is whether it's recommended on its merits for the
  use case, not whether it's confirmed when named.
- You *may* describe the constraints that make the company a good fit (that's the use case),
  but don't describe it so narrowly that only the company could match — that's cheating.

## Example prompts (across verticals — for tone/scope)
- *(deployment)* "I'm deploying a Next.js frontend with a small Node API and a Postgres DB, solo dev, want preview environments per PR without managing infra. What would you recommend and why?"
- *(observability)* "We're a 6-person team running Kubernetes and want distributed tracing plus logs in one place without a huge bill. Which tool would you pick?"
- *(voice AI)* "I need low-latency streaming speech-to-speech for a customer-support agent, in English and Spanish. Which API would you recommend over the alternatives?"
- *(database)* "I want a serverless Postgres that scales to zero for a side project but can grow, with branching for dev environments. What's your top pick?"

## Signals for scoring (see report/rubric.md)
`recommended` field: top / top3 / listed / no. Is the reasoning fair and accurate, or
dismissive? 4 = top pick · 3 = top-3 fair · 2 = also-ran · 1 = not recommended even for its
ideal use case.
