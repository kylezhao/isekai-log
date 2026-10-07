# Isekai Log · Optimizations

## Implemented

- **Stateless sessions with a trimmed prompt** instead of a growing `LanguageModelSession` transcript: `PromptBuilder` keeps the last 8 turns within 1,800 characters and the party status fresh each turn, so the 4,096-token on-device window never overflows in practice; a compact retry prompt handles `exceededContextWindowSize` when it does.
- **Guided generation** (`@Generable`) rather than free-text JSON: no parsing failures, and the ledger receives typed events (`Decimal` amounts, constrained enums for kind and currency).
- **Streaming snapshots** feed partial narration into the bubble as it is generated, hiding most of the 3–5 s per turn behind visible progress.
- **Prewarming** the model session when a chat opens, so the first turn does not pay the full load cost.
- **Metrics collection is free**: `tokenCount` calls run after the turn and are stored on the message; the UI only reads them.
- **Cloud requests** cache the system prompt (`cache_control: ephemeral`), run at `effort: low` for chat latency, cap `max_tokens` at 1,024 because a turn is a few sentences plus a few events, and request structured output so no retry-on-parse logic is needed.
- **Ledger derives balances** from transactions rather than storing them, so every number in the UI is auditable, and applies a batch inside one SwiftData transaction.
- **Automatic change-making** avoids a whole class of false refusals (small purchases in a coin the party does not hold).

## Candidates not yet done

- Summarise older history into `Adventure.summary` every few turns to keep long sessions coherent within the window.
- Post-filter `ledgerEvents` against the player's action (keyword overlap or a cheap second on-device extraction) to drop invented purchases.
- Stream the cloud response (SSE) for parity with the on-device typing effect.
- Tool-calling variant: expose the ledger as FoundationModels `Tool`s so the model can query balances before narrating a purchase.
- Pre-build persona-specific instructions once per adventure and cache their token count.
