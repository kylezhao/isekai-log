//
//  ScriptedNarratorEngine.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// Deterministic narrator that needs no model. Used for the simulator (where Apple Intelligence may be
/// unavailable), SwiftUI previews and end-to-end tests of the ledger pipeline.
final class ScriptedNarratorEngine: NarratorEngine {
    let descriptor = EngineDescriptor(mode: .scripted, displayName: "Scripted Demo", modelID: "rule-based")

    /// Delay between streamed words. Zero in tests.
    private let wordDelay: Duration

    init(wordDelay: Duration = .milliseconds(28)) {
        self.wordDelay = wordDelay
    }

    func availability() async -> EngineAvailability { .available }

    func prewarm(instructions: String) async {}

    func respond(to request: TurnRequest) -> AsyncThrowingStream<TurnUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let clock = ContinuousClock()
                    let start = clock.now
                    let turn = Self.makeTurn(for: request)
                    var streamed = ""
                    for word in turn.narration.split(separator: " ", omittingEmptySubsequences: false) {
                        try Task.checkCancellation()
                        streamed += (streamed.isEmpty ? "" : " ") + word
                        continuation.yield(.partialNarration(streamed))
                        if self.wordDelay > .zero { try await Task.sleep(for: self.wordDelay) }
                    }
                    let metrics = TurnMetrics(
                        engine: self.descriptor,
                        latency: clock.now - start,
                        inputTokens: request.prompt.count / 4,
                        outputTokens: turn.narration.count / 4,
                        retried: false
                    )
                    continuation.yield(.completed(turn, metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error is CancellationError ? NarratorError.cancelled : NarratorError.other(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Script

    enum Intent { case begin, sell, buy, transfer, fight, explore, talk, other }

    static func intent(for input: String) -> Intent {
        let text = input.lowercased()
        if text.contains("adventure begins") || text.contains("introduce") { return .begin }
        if text.containsAny(["sell", "sold", "reward", "bounty", "loot", "earn"]) { return .sell }
        if text.containsAny(["give", "transfer", "lend", "pay ", "donate", "tip "]) && text.contains(" to ") { return .transfer }
        if text.containsAny(["buy", "bought", "purchase", "pay", "spend", "rent", "inn", "potion"]) { return .buy }
        if text.containsAny(["attack", "fight", "slay", "strike", "cast", "defend"]) { return .fight }
        if text.containsAny(["explore", "enter", "walk", "travel", "head", "go ", "search", "open"]) { return .explore }
        if text.containsAny(["talk", "ask", "speak", "greet", "say", "tell"]) { return .talk }
        return .other
    }

    static func makeTurn(for request: TurnRequest) -> NarratorTurn {
        let voice = request.personaName
        let events = NaturalLanguageLedgerParser.heuristic(request.playerInput)
        let eventSummary = events.map { "\($0.money.formatted()) for \($0.memo)" }
        switch intent(for: request.playerInput) {
        case .begin:
            return NarratorTurn(
                narration: "Light floods your eyes as \(voice) leans over you. \"Welcome, traveler. This is Brightwater, edge of the known world. Your pockets are nearly empty, your skill is untested, and the guild board is already filling with requests.\" A cart rattles past, and the smell of fresh bread drifts from a stall.",
                suggestedActions: ["Visit the Adventurers' Guild", "Buy bread for 5 silver", "Ask about the forest bounty"]
            )
        case .sell:
            return NarratorTurn(
                narration: "The merchant turns your goods over twice, grunts, and counts out coins onto the counter. \(voice) notes the sum with satisfaction. \(eventSummary.isEmpty ? "Nothing of value changes hands this time." : "Coins counted: \(eventSummary.joined(separator: ", ")).")",
                ledgerEvents: events,
                suggestedActions: ["Buy a healing potion", "Check the quest board", "Head for the forest"]
            )
        case .buy:
            return NarratorTurn(
                narration: "You reach for your purse as the shopkeeper names the price. \(voice) watches to see whether the ledger agrees. \(eventSummary.isEmpty ? "The price turns out to be negotiable, and no coin is spent." : "Price quoted: \(eventSummary.joined(separator: ", ")).") Outside, the evening bell rings.",
                ledgerEvents: events,
                suggestedActions: ["Rest at the inn for 2 gold", "Explore the old quarry", "Count your coins"]
            )
        case .transfer:
            return NarratorTurn(
                narration: "You pass the coins over with a steady hand. \(voice) watches the exchange closely and makes a note. \(eventSummary.isEmpty ? "The recipient waves the money away for now." : "Offered: \(eventSummary.joined(separator: ", ")).")",
                ledgerEvents: events,
                suggestedActions: ["Ask for a favor in return", "Return to the guild", "Explore the market"]
            )
        case .fight:
            return NarratorTurn(
                narration: "Steel sings as you close the distance. The creature lunges, misses, and your counterblow lands true. \(voice) cheers you on as it collapses into glittering motes, leaving a small pouch behind.",
                ledgerEvents: [LedgerEvent(kind: "income", amount: 12, currency: "S", memo: "pouch dropped by the monster")],
                suggestedActions: ["Search the clearing", "Return to town", "Press deeper into the forest"]
            )
        case .explore:
            return NarratorTurn(
                narration: "You set out along the mossy road. Lanterns bob in the distance where a caravan has made camp, and something glints in the ditch beside you. \(voice) suggests you keep your eyes open.",
                suggestedActions: ["Pick up the glinting object", "Approach the caravan", "Make camp"]
            )
        case .talk:
            return NarratorTurn(
                narration: "The stranger studies you for a long moment before answering. \"New here? Then listen well.\" They tell you of a bounty on the river wolves and a merchant who pays well for pelts. \(voice) files the information away.",
                suggestedActions: ["Take the river wolf bounty", "Ask about the merchant", "Thank them and leave"]
            )
        case .other:
            return NarratorTurn(
                narration: "You act, and the world answers in its own strange way. \(voice) tilts their head, curious to see what you will try next. \(eventSummary.isEmpty ? "" : "Coins mentioned: \(eventSummary.joined(separator: ", ")).")",
                ledgerEvents: events,
                suggestedActions: ["Look around", "Check the quest board", "Visit the market"]
            )
        }
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
