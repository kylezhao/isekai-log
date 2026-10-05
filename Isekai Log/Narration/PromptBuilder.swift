//
//  PromptBuilder.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// Turns the adventure state into the instructions and prompt handed to a narrator engine.
/// Kept free of SwiftData so it can be unit-tested with plain values.
struct PromptBuilder: Sendable {
    struct PartyStatus: Sendable, Equatable {
        var name: String
        var members: [String]
        var balances: [Money]
        var isPlayerParty: Bool
    }

    struct Input: Sendable {
        var premise: String
        var personaName: String
        var personalityInstructions: String
        var parties: [PartyStatus]
        var summary: String
        var history: [TurnHistoryItem]
        var playerInput: String
        var temperature: Double
        var languageName: String
    }

    /// Characters of history kept in the full prompt. The on-device model has a 4,096-token window.
    var historyBudget = 1_800
    /// Characters of history kept in the compact prompt used after a context overflow.
    var compactHistoryBudget = 500
    var recentTurns = 8

    func makeRequest(_ input: Input) -> TurnRequest {
        let worldState = renderWorldState(input.parties)
        let fullHistory = renderHistory(input.history, summary: input.summary, budget: historyBudget, turns: recentTurns)
        let compactHistory = renderHistory(input.history, summary: "", budget: compactHistoryBudget, turns: 2)

        return TurnRequest(
            instructions: makeInstructions(input),
            prompt: renderPrompt(worldState: worldState, history: fullHistory, playerInput: input.playerInput),
            compactPrompt: renderPrompt(worldState: worldState, history: compactHistory, playerInput: input.playerInput),
            history: Array(input.history.suffix(recentTurns)),
            worldState: worldState,
            playerInput: input.playerInput,
            personaName: input.personaName,
            temperature: input.temperature
        )
    }

    func makeInstructions(_ input: Input) -> String {
        let personality = input.personalityInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        You narrate an isekai roleplay adventure: the player was transported from modern Japan to another world.

        Your persona (stay in it at all times):
        \(personality.isEmpty ? "A fair and vivid fantasy narrator." : personality)

        World premise:
        \(input.premise)

        Rules:
        - Narrate in second person ("you"). Keep each turn to 2 to 5 sentences and end with a hook or a choice.
        - Keep it PG-13: fantasy action is fine, no graphic gore and nothing sexual.
        - Money is tracked by a ledger outside your control. Report every coin gained, spent or handed over \
        through ledgerEvents with exact amounts. Never state balances yourself; the party status you receive is the truth.
        - Only report money that the player's latest action actually moved. Never invent purchases, fees or finds the player did not make.
        - If the party cannot afford something, the purchase fails and you narrate the refusal. Do not report an event for it.
        - Exchange rates: \(CurrencyConverter.exchangeTable) Typical prices: meal 5 S, inn night 2 G, potion 15 G, iron sword 40 G.
        - Offer up to three short suggested actions.
        - Write in \(input.languageName).
        """
    }

    func renderWorldState(_ parties: [PartyStatus]) -> String {
        guard !parties.isEmpty else { return "No party yet." }
        var lines: [String] = []
        for party in parties.sorted(by: { $0.isPlayerParty && !$1.isPlayerParty }) {
            let members = party.members.isEmpty ? "no members" : party.members.joined(separator: ", ")
            let balances = party.balances.isEmpty ? "no money" : party.balances.map { $0.formatted() }.joined(separator: ", ")
            if party.isPlayerParty {
                let goldTotal = party.balances.reduce(Decimal.zero) { $0 + $1.converted(to: .gold).amount }
                let yen = Money(amount: goldTotal, currency: .gold).converted(to: .yen)
                lines.append("Player party \"\(party.name)\": \(members). Treasury: \(balances) (about \(yen.formatted()) in the old world).")
            } else {
                lines.append("Other party \"\(party.name)\": \(members). Holds: \(balances).")
            }
        }
        return lines.joined(separator: "\n")
    }

    func renderHistory(_ history: [TurnHistoryItem], summary: String, budget: Int, turns: Int) -> String {
        var lines: [String] = []
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            lines.append("Earlier: \(trimmedSummary)")
        }
        var used = 0
        var recent: [String] = []
        for item in history.suffix(turns).reversed() {
            let label = item.role == .player ? "Player" : "Narrator"
            var text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if used + text.count > budget {
                let remaining = max(0, budget - used)
                guard remaining > 40 else { break }
                text = String(text.prefix(remaining)) + "…"
            }
            used += text.count
            recent.insert("\(label): \(text)", at: 0)
        }
        lines.append(contentsOf: recent)
        return lines.isEmpty ? "The adventure is just beginning." : lines.joined(separator: "\n")
    }

    func renderPrompt(worldState: String, history: String, playerInput: String) -> String {
        """
        [Party status]
        \(worldState)

        [Story so far]
        \(history)

        [Player's action]
        \(playerInput)
        """
    }

    /// The language the narrator should write in, derived from the device locale.
    static var preferredLanguageName: String {
        let locale = Locale.current
        guard let code = locale.language.languageCode?.identifier,
              let name = Locale(identifier: "en").localizedString(forLanguageCode: code) else {
            return "English"
        }
        return name
    }
}
