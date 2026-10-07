# Playtest logs

Each file is a complete session exported by the app's own Markdown exporter, recorded by
`PlaytestRecorderTests` against the real on-device model (Apple Intelligence, iPhone 16e simulator,
iOS 26.5). The scripted player actions are fixed per scenario, so the logs double as test cases:
the same actions can be replayed against a new build and the ledger section compared.

| Scenario | Narrator | World | What it exercises |
| --- | --- | --- | --- |
| `01-goddess-merchant-town` | Aqualis (goddess) | Classic reincarnation | income, purchase, impossible purchase (refusal), transfer to a new party, no-money turn |
| `02-receptionist-guild-fees` | Mira (guild receptionist) | Dungeon city | fees paid to a named party, bounty income, selling drops, lodging |
| `03-demon-lord-temptation` | Vexarion (demon lord) | Merchant reborn | haggling, buying in silver, a tempting shortcut, a balance question |

## Iteration from the logs

**Round 1 (`round-1-debug/`)** was the first full run after the game loop worked. Reading the
ledger sections showed two problems the UI tests had not caught:

1. The recorder sent the next action before the previous turn's task had started, so two actions
   were dropped and the last turn ended with empty narration. This exposed a race in the app's own
   `send`: `isResponding` was only set inside the task. Fixed by claiming the turn synchronously.
2. The on-device model **re-reports earlier money events** on later turns because it sees them in
   the story history: the pelt sale was booked twice and the potion three times, once with the sign
   flipped, and a donation came back as income. Prompt rules alone did not stop this.

**Round 2 (`round-2/`)** adds `LedgerEventDeduplicator`: an event whose amount and currency match a
transaction booked in the previous two narrator turns, with at least one shared memo keyword, is
treated as a restatement and shown as "Already recorded" instead of being booked. The same check
runs within a single turn's batch, so a sign-flipped duplicate of a fresh event is dropped too.
Compare the ledger tables between the two rounds for the same actions.

Remaining model behaviour visible in both rounds, kept for the bug list: unrequested extra events
(an inn stay nobody asked for), coin totals stated in narration, and repetitive scene-setting when
the model does not know how to react to an action (the castle purchase).
