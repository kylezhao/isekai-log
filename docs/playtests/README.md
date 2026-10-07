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

Round 2 then showed three more defects: the model named the player's own party as the counterparty
("A party cannot transfer money to itself"), it flipped the sign on purchases and donations
("+10 S bought salt", "+5 G Donated to the orphanage"), and one turn failed to decode
("Failed to deserialize a Generable type").

**Round 3 (`round-3/`)** adds `LedgerEventSanitizer` (expense/income verbs in the memo override a
wrong kind; events with no money verb such as "You check your gold" are dropped), treats a
self-counterparty as the world, and retries a turn once with the compact prompt on a decoding
failure. In round 3 every turn decoded, donations and purchases carry the right sign, and the
pelts/potion restatements all surface as "Already recorded" instead of double-booking. Mean latency
per turn fell to 3.2–4.1 s as prompts stayed shorter.

Remaining model behaviour visible in all rounds, kept for the bug list: unrequested extra events
(a potion "resold" for 15 G, wolf pelts sold in a dungeon city), coin totals stated in narration,
and repetitive scene-setting when the model does not know how to react to an action (the castle
purchase).
