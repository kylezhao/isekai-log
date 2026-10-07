# Isekai Log · Models, parameters and metrics

## Narrator engines

| Engine | Model | Where | Parameters |
| --- | --- | --- | --- |
| On-device | Apple `SystemLanguageModel` (Apple Intelligence foundation model, ~3B parameters, 4,096-token context) | iPhone / Simulator | `useCase: .general`, `guardrails: .permissiveContentTransformations`, temperature 0.8 (user adjustable 0–1.5), `maximumResponseTokens: 700`, guided generation into the `@Generable` `NarratorTurn` struct (narration, ≤4 ledger events, ≤3 suggested actions), streamed snapshots, one retry with a compact prompt on `exceededContextWindowSize` |
| Cloud | `claude-opus-5-5` (default), `claude-sonnet-5-5`, `claude-haiku-4-5` | Anthropic Messages API | `max_tokens: 1024`, `output_config.format` JSON schema mirroring `NarratorTurn`, `output_config.effort: "low"`, adaptive thinking (model default), `fallbacks: "default"` with beta `server-side-fallback-2026-07-01`, system prompt cached with `cache_control: ephemeral`; Haiku 4.5 instead receives `temperature` and no effort/fallbacks |
| Scripted | rule-based | anywhere | keyword intent detection, deterministic templates; used for UI tests and demos |

Prompt budget (`PromptBuilder`): instructions ≈ 300 tokens (persona + rules), party status ≈ 100, history trimmed to 1,800 characters over the last 8 turns, compact retry prompt trims history to 500 characters over 2 turns.

## Natural-language ledger parser

On-device `SystemLanguageModel` with guided generation into `ParsedEvents` (≤4 `LedgerEvent`), temperature 0.1, `maximumResponseTokens: 300`; keyword fallback when the model is unavailable.

## Measured metrics

Per-turn metrics are stored on every narrator message (engine, model id, latency, input and output tokens) and appear under each reply and in the Markdown export.

| Run | Device | Latency per turn | Tokens in → out | Notes |
| --- | --- | --- | --- | --- |
| On-device, simulator (Mac host, iPhone 16e simulator, iOS 26.5) | first turn 5.4 s, later turns 3.2–5.0 s | 470–760 → 55–90 | first turn includes model load |
| On-device, simulator, recorded playtests round 1 (3 sessions, 15 turns) | 4.9–9.2 s, mean 7.5 s | 580–990 → 70–135 | prompts grow with history; see `docs/playtests` run metrics |
| On-device, simulator, recorded playtests round 3 (3 sessions, 15 turns) | 2.1–5.4 s, mean 3.2–4.1 s | see logs | 0 decode failures after the retry; built with Xcode 27.0 against the iOS 26.5 runtime |
| On-device, iPhone 16e (Kyle's device, 2026-10-06) | ≈ 5.0 s per turn | ≈ 590 → 60 | from the device screenshot in the showcase |
| Scripted | 1.0–1.7 s (streaming animation) | n/a | deterministic |
| Cloud | not measured live | n/a | no API key available during development; request shape is unit-tested |

The recorded playtest logs in `docs/playtests/` include a run-metrics section per session (turn count, min / mean / max latency, mean tokens, ledger totals, refusals).

## Quality observations

- The 3B on-device model follows the structured schema reliably; every turn decoded.
- It tends to add plausible but unrequested money events (an inn stay, a sword sale) alongside the real one. Prompt rules reduce but do not eliminate this; see `BUGS.md`.
- It sometimes narrates coin totals despite the rule not to; the ledger remains the source of truth in the UI.
- Refusals or guardrail stops were not observed in PG-13 fantasy content during testing.
