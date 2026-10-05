//
//  NaturalLanguageLedgerParser.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import FoundationModels

/// Turns a sentence like "spent 20 silver on bread" into ledger events.
///
/// Uses the on-device model with guided generation when it is available and falls back to a
/// keyword heuristic otherwise, so natural-language bookkeeping works offline on every device.
enum NaturalLanguageLedgerParser {
    @Generable(description: "Money events found in a sentence written by the player.")
    struct ParsedEvents {
        @Guide(description: "Every money event mentioned. Empty if the sentence mentions no money.", .maximumCount(4))
        var events: [LedgerEvent]
    }

    enum Source: Sendable, Equatable { case onDeviceModel, heuristic }

    struct Result: Sendable, Equatable {
        var events: [LedgerEvent]
        var source: Source
    }

    /// Parses with the on-device model when possible. Never throws: falls back to the heuristic.
    static func parse(_ text: String, model: SystemLanguageModel = .default) async -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(events: [], source: .heuristic) }
        guard model.isAvailable else { return Result(events: heuristic(trimmed), source: .heuristic) }

        let session = LanguageModelSession(model: model, instructions: """
        You extract money events from a sentence written by a player of a fantasy roleplay game. \
        Currencies: G = gold, S = silver, C = copper; "coins" means gold. \
        kind is income when the player gains money, expense when the player spends money, \
        transfer when the player gives money to a named person or group (set counterparty). \
        Amounts are positive. Memo is a few words. Return no events if no money is mentioned.
        """)
        do {
            let response = try await session.respond(
                to: trimmed,
                generating: ParsedEvents.self,
                options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 300)
            )
            let events = response.content.events.filter { $0.amount > 0 }
            return Result(events: events, source: .onDeviceModel)
        } catch {
            return Result(events: heuristic(trimmed), source: .heuristic)
        }
    }

    /// Keyword-based parser. Finds "<number> <currency>" pairs and classifies the sentence by its verbs.
    static func heuristic(_ text: String) -> [LedgerEvent] {
        let lowered = text.lowercased()
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(gold|silver|copper|coins?|g|s|c|¥|yen)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(lowered.startIndex..., in: lowered)
        let matches = regex.matches(in: lowered, options: [], range: range)
        guard !matches.isEmpty else { return [] }

        let kind: String
        let counterparty = transferRecipient(in: text)
        if counterparty != nil {
            kind = "transfer"
        } else if lowered.containsAny(["sell", "sold", "earn", "earned", "reward", "bounty", "loot", "found", "receive", "received", "win", "won", "paid me", "tipped me"]) {
            kind = "income"
        } else {
            kind = "expense"
        }

        var events: [LedgerEvent] = []
        for match in matches {
            guard let amountRange = Range(match.range(at: 1), in: lowered),
                  let unitRange = Range(match.range(at: 2), in: lowered) else { continue }
            let amountText = lowered[amountRange].replacingOccurrences(of: ",", with: ".")
            guard let amount = Decimal(string: amountText), amount > 0 else { continue }
            let unit = String(lowered[unitRange])
            let currency: Currency
            switch unit {
            case "coin", "coins": currency = .gold
            case "¥", "yen": continue // old-world money cannot be spent here
            default: currency = Currency.resolve(unit) ?? .gold
            }
            events.append(LedgerEvent(
                kind: kind,
                amount: amount,
                currency: currency.code,
                memo: memo(from: text),
                counterparty: counterparty ?? ""
            ))
        }
        return events
    }

    /// Finds "to <Name>" and returns the capitalized name that follows, if any.
    private static func transferRecipient(in text: String) -> String? {
        let pattern = #"\b(?:to|for)\s+(?:the\s+)?([A-Z][\w']*(?:\s+[A-Z][\w']*)*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let nameRange = Range(match.range(at: 1), in: text) else { return nil }
        let lowered = text.lowercased()
        guard lowered.containsAny(["give", "gave", "transfer", "lend", "lent", "pay", "paid", "donate", "tip", "hand"]) else { return nil }
        return String(text[nameRange])
    }

    private static func memo(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 60 { return cleaned }
        return String(cleaned.prefix(57)) + "…"
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
