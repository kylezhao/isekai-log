# Isekai Log · Bug list

## Found and fixed during development

| # | Bug | How it was found | Fix |
| --- | --- | --- | --- |
| 1 | Opening turn invented purchases (inn stay, loaf of bread) the player never made | On-device UI test, labels dump | Opening prompt states that nothing is bought in the introduction and `ledgerEvents` must be empty |
| 2 | A 1-copper purchase was refused while the party held 8 gold, because balances were checked per currency | On-device playthrough | Ledger makes change automatically from a larger coin and records the exchange pair |
| 3 | Refusal note quoted the shortfall ("needs 110 G") instead of the price for a 120 G purchase | Device screenshot | Refusals report the full price and the total purse |
| 4 | Composer placeholder and caret sat ~4 pt below the send button's centre | Device screenshot, measured with cropped Simulator screenshots | 4 pt bottom padding on the vertical-axis text field and a centred row |
| 5 | "Ledger refused" note hidden behind the suggestion chips when they appeared after a turn | UI test screenshot | Chat re-scrolls to the bottom when suggestions change |
| 6 | Scripted demo narrator claimed "Recorded: -1,000 G" for a purchase the ledger refused | UI test screenshot | Neutral wording ("Price quoted") so the ledger alone states what was recorded |
| 7 | Two sends in quick succession could both start a turn because `isResponding` was set inside the task | Playtest recorder sent actions back to back; two actions were dropped and a turn ended with empty text | `send` claims the turn synchronously before starting the task |
| 8 | Currency converter pickers wrapped vertically and overlapped the result | UI test screenshot | Pickers on their own row with fixed size |
| 9 | On-device model re-reported earlier money events on later turns (pelt sale booked twice, potion three times, a donation as income) | Round-1 playtest logs (`docs/playtests/round-1-debug`) | `LedgerEventDeduplicator` drops events matching a transaction from the previous two turns by amount, currency and memo keywords, and duplicates within a batch |
| 10 | Model flipped event kinds (purchases and donations reported as income) and reported balance checks as events | Round-2 playtest logs | `LedgerEventSanitizer` corrects the kind from memo verbs and drops events with no money verb |
| 11 | Model named the player's own party as the counterparty, which the ledger rejected as a self-transfer | Round-2 playtest logs | A self-counterparty is treated as "the world" |
| 12 | One turn failed with "Failed to deserialize a Generable type from model output" | Round-2 playtest logs | One retry with the compact prompt on `decodingFailure`; none in round 3 |

## Known issues

| # | Issue | Impact | Mitigation / next step |
| --- | --- | --- | --- |
| A | On-device model adds unrequested money events on normal turns (e.g. "-2 G night at the inn" after a pelt sale) | Ledger books events the player did not ask for | Ledger rule leads the instructions with a worked example; candidate: post-filter events whose memo is unrelated to the action, or a second extraction pass |
| B | On-device model sometimes states balances in narration | Can contradict the ledger after a refusal | Status window and ledger are authoritative; stronger rule or post-edit of numbers |
| C | NPC parties can show negative balances (they are assumed to have deep pockets) | Looks odd in the Party screen | Display "paid out" instead of a negative figure, or seed NPC parties with funds |
| D | Cloud mode not verified live | Request/response shapes are unit-tested only | Enter an API key in Settings and run a session |
| E | Context window of 4,096 tokens | Long sessions rely on trimming; summaries are not yet generated | Add a summarisation turn into `Adventure.summary` every N turns |
| F | Build warnings: main-actor isolated `Equatable` conformance of `Money` used in nonisolated code (Swift 6 mode error) | None at runtime | Mark the value types `nonisolated` or move off the MainActor default isolation |
