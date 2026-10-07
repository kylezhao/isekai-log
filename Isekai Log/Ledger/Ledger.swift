//
//  Ledger.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData

/// Drops narrator events that merely restate money already booked in the previous turns.
/// Small on-device models tend to re-emit earlier events when they see them in the story history.
enum LedgerEventDeduplicator {
    static let stopWords: Set<String> = ["the", "a", "an", "of", "for", "to", "at", "in", "on", "and", "with", "from", "sold", "bought", "buy", "sell", "paid", "pay", "gave", "give", "purchase", "purchased", "donation", "donated"]

    static func keywords(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 && !stopWords.contains($0) })
    }

    /// Returns the events to keep and the ones judged to be repeats of `recent` transactions.
    static func split(_ events: [LedgerEvent], recent: [LedgerTransaction]) -> (keep: [LedgerEvent], repeats: [LedgerEvent]) {
        var keep: [LedgerEvent] = []
        var repeats: [LedgerEvent] = []
        var seenInBatch: [(Decimal, String, Set<String>)] = []
        for event in events {
            let words = keywords(event.memo)
            let matchesRecent = recent.contains { transaction in
                transaction.amount == event.amount.rounded(scale: 2)
                    && transaction.currencyCode == event.resolvedCurrency.code
                    && (words.isEmpty || !words.isDisjoint(with: keywords(transaction.memo)))
            }
            let matchesBatch = seenInBatch.contains { $0.0 == event.amount && $0.1 == event.resolvedCurrency.code && (words.isEmpty || !words.isDisjoint(with: $0.2)) }
            if matchesRecent || matchesBatch {
                repeats.append(event)
            } else {
                keep.append(event)
                seenInBatch.append((event.amount, event.resolvedCurrency.code, words))
            }
        }
        return (keep, repeats)
    }
}

/// Corrects obviously wrong event kinds and drops "events" that describe no money moving.
/// The on-device model marks purchases as income now and then, and reports balance checks as events.
enum LedgerEventSanitizer {
    static let expenseVerbs = ["bought", "buy", "purchas", "paid", "pay ", "spent", "spend", "donat", "gave", "give", "rent", "fee", "tip", "bribe", "cost", "hired", "lodging", "night at"]
    static let incomeVerbs = ["sold", "sell", "earn", "reward", "bounty", "found", "receiv", "loot", "won", "wage", "tip from", "paid you", "payment for"]

    struct Result: Equatable {
        var events: [LedgerEvent]
        var dropped: [LedgerEvent]
        var corrected: [LedgerEvent]
    }

    static func sanitize(_ events: [LedgerEvent]) -> Result {
        var kept: [LedgerEvent] = []
        var dropped: [LedgerEvent] = []
        var corrected: [LedgerEvent] = []
        for var event in events {
            let memo = event.memo.lowercased()
            let hasExpense = expenseVerbs.contains { memo.contains($0) }
            let hasIncome = incomeVerbs.contains { memo.contains($0) }
            if !hasExpense, !hasIncome, event.transactionKind != .transfer {
                // "You check your gold." carries no transaction.
                dropped.append(event)
                continue
            }
            if event.transactionKind != .transfer {
                if hasExpense, !hasIncome, event.transactionKind == .income {
                    event.kind = TransactionKind.expense.rawValue; corrected.append(event)
                } else if hasIncome, !hasExpense, event.transactionKind == .expense {
                    event.kind = TransactionKind.income.rawValue; corrected.append(event)
                }
            }
            kept.append(event)
        }
        return Result(events: kept, dropped: dropped, corrected: corrected)
    }
}

/// Bookkeeping for an adventure. Validates every money event, applies the accepted ones atomically,
/// and derives balances from the transaction history.
@MainActor
struct Ledger {
    struct Rejection: Identifiable, Equatable, Sendable {
        let id = UUID()
        let event: LedgerEvent
        let reason: String
    }

    struct Outcome: Equatable {
        var applied: [LedgerTransaction]
        var rejected: [Rejection]

        var isEmpty: Bool { applied.isEmpty && rejected.isEmpty }
    }

    enum LedgerError: LocalizedError, Equatable {
        case nonPositiveAmount
        case unknownCurrency(String)
        case insufficientFunds(needed: Money, available: Money)
        case missingPlayerParty
        case samePartyTransfer

        var errorDescription: String? {
            switch self {
            case .nonPositiveAmount: String(localized: "Amount must be positive.")
            case .unknownCurrency(let code): String(localized: "Unknown currency \(code).")
            case .insufficientFunds(let needed, let available):
                String(localized: "Not enough funds: needs \(needed.formatted()), has \(available.formatted()).")
            case .missingPlayerParty: String(localized: "The adventure has no player party.")
            case .samePartyTransfer: String(localized: "A party cannot transfer money to itself.")
            }
        }
    }

    let modelContext: ModelContext

    // MARK: - Balances

    func balance(of party: Party, in currency: Currency) -> Decimal {
        var total = Decimal.zero
        for transaction in party.incoming where transaction.currencyCode == currency.code {
            total += transaction.amount
        }
        for transaction in party.outgoing where transaction.currencyCode == currency.code {
            total -= transaction.amount
        }
        return total
    }

    /// Non-zero balances in catalog order.
    func balances(of party: Party) -> [Money] {
        Currency.inWorld.compactMap { currency in
            let amount = balance(of: party, in: currency)
            return amount == 0 ? nil : Money(amount: amount, currency: currency)
        }
    }

    /// Everything the party holds, expressed in gold.
    func netWorthInGold(of party: Party) -> Decimal {
        Currency.inWorld.reduce(Decimal.zero) { partial, currency in
            partial + CurrencyConverter.convert(balance(of: party, in: currency), from: currency, to: .gold)
        }
    }

    // MARK: - Parties

    func party(named name: String, in adventure: Adventure, createIfMissing: Bool) -> Party? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let existing = adventure.parties.first(where: { $0.name.compare(needle, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existing
        }
        guard createIfMissing else { return nil }
        let party = Party(name: needle, isPlayerParty: false, adventure: adventure)
        modelContext.insert(party)
        adventure.parties.append(party)
        return party
    }

    // MARK: - Recording

    /// Records one movement of money after validating it. Only the player party is protected from overdraft:
    /// merchants, guilds and other world parties are assumed to have deep pockets.
    @discardableResult
    func record(
        kind: TransactionKind,
        amount: Decimal,
        currency: Currency,
        memo: String,
        from: Party?,
        to: Party?,
        adventure: Adventure,
        source: ChatMessage?,
        origin: TransactionOrigin
    ) throws -> LedgerTransaction {
        guard amount > 0 else { throw LedgerError.nonPositiveAmount }
        if let from, let to, from.id == to.id { throw LedgerError.samePartyTransfer }
        if let from, from.isPlayerParty {
            let available = balance(of: from, in: currency)
            if available < amount {
                // Pay with other coins when the purse holds enough overall: the merchant makes change.
                try makeChange(for: from, shortfall: amount - available, price: amount, in: currency, adventure: adventure, source: source)
            }
        }
        let transaction = LedgerTransaction(
            kind: kind,
            amount: amount.rounded(scale: 2),
            currency: currency,
            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines),
            origin: origin,
            adventure: adventure,
            fromParty: from,
            toParty: to,
            sourceMessage: source
        )
        modelContext.insert(transaction)
        adventure.transactions.append(transaction)
        from?.outgoing.append(transaction)
        to?.incoming.append(transaction)
        source?.transactions.append(transaction)
        adventure.updatedAt = .now
        return transaction
    }

    /// Exchanges coins from a larger holding so `party` can pay `shortfall` in `currency`.
    /// Records the exchange as a system expense/income pair so the audit trail shows it.
    private func makeChange(for party: Party, shortfall: Decimal, price: Decimal, in currency: Currency, adventure: Adventure, source: ChatMessage?) throws {
        let neededInGold = CurrencyConverter.convert(shortfall, from: currency, to: .gold)
        let candidates = Currency.inWorld.filter { $0 != currency }.sorted { $0.goldValue > $1.goldValue }
        for other in candidates {
            let holding = balance(of: party, in: other)
            guard holding > 0, holding * other.goldValue >= neededInGold else { continue }
            let exchanged = CurrencyConverter.convert(neededInGold, from: .gold, to: other).rounded(scale: other.fractionDigits, mode: .up)
            let received = CurrencyConverter.convert(exchanged, from: other, to: currency).rounded(scale: currency.fractionDigits)
            let memo = String(localized: "Changed \(Money(amount: exchanged, currency: other).formatted()) into \(Money(amount: received, currency: currency).formatted())")
            let out = LedgerTransaction(kind: .expense, amount: exchanged, currency: other, memo: memo, origin: .system, adventure: adventure, fromParty: party, toParty: nil, sourceMessage: source)
            let inbound = LedgerTransaction(kind: .income, amount: received, currency: currency, memo: memo, origin: .system, adventure: adventure, fromParty: nil, toParty: party, sourceMessage: source)
            for transaction in [out, inbound] {
                modelContext.insert(transaction)
                adventure.transactions.append(transaction)
            }
            party.outgoing.append(out)
            party.incoming.append(inbound)
            return
        }
        throw LedgerError.insufficientFunds(
            needed: Money(amount: price, currency: currency),
            available: Money(amount: netWorthInGold(of: party).rounded(scale: 2), currency: .gold)
        )
    }

    /// Applies a batch of narrator or player events. Events are validated in order against the running
    /// balance; accepted ones are committed together, rejected ones are reported with a reason.
    func apply(
        _ events: [LedgerEvent],
        to adventure: Adventure,
        source: ChatMessage?,
        origin: TransactionOrigin
    ) -> Outcome {
        guard !events.isEmpty else { return Outcome(applied: [], rejected: []) }
        guard let playerParty = adventure.playerParty else {
            return Outcome(applied: [], rejected: events.map { Rejection(event: $0, reason: LedgerError.missingPlayerParty.localizedDescription) })
        }

        var applied: [LedgerTransaction] = []
        var rejected: [Rejection] = []

        do {
            try modelContext.transaction {
                for event in events {
                    do {
                        let transaction = try apply(event, playerParty: playerParty, adventure: adventure, source: source, origin: origin)
                        applied.append(transaction)
                    } catch let error as LedgerError {
                        rejected.append(Rejection(event: event, reason: error.localizedDescription))
                    }
                }
            }
        } catch {
            // The whole batch rolled back. Report every event as rejected so nothing is silently lost.
            return Outcome(applied: [], rejected: events.map { Rejection(event: $0, reason: error.localizedDescription) })
        }
        return Outcome(applied: applied, rejected: rejected)
    }

    private func apply(
        _ event: LedgerEvent,
        playerParty: Party,
        adventure: Adventure,
        source: ChatMessage?,
        origin: TransactionOrigin
    ) throws -> LedgerTransaction {
        guard let currency = Currency.resolve(event.currency), Currency.inWorld.contains(currency) else {
            throw LedgerError.unknownCurrency(event.currency)
        }
        var counterparty = event.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        // The model occasionally names the player's own party as the other side; that means "the world".
        if let existing = party(named: counterparty, in: adventure, createIfMissing: false), existing.id == playerParty.id {
            counterparty = ""
        }
        switch event.transactionKind {
        case .income:
            let from = counterparty.isEmpty ? nil : party(named: counterparty, in: adventure, createIfMissing: true)
            return try record(kind: .income, amount: event.amount, currency: currency, memo: event.memo, from: from, to: playerParty, adventure: adventure, source: source, origin: origin)
        case .expense:
            let to = counterparty.isEmpty ? nil : party(named: counterparty, in: adventure, createIfMissing: true)
            return try record(kind: .expense, amount: event.amount, currency: currency, memo: event.memo, from: playerParty, to: to, adventure: adventure, source: source, origin: origin)
        case .transfer:
            guard let other = party(named: counterparty, in: adventure, createIfMissing: true) else {
                // A transfer with no named recipient is just money leaving the party.
                return try record(kind: .expense, amount: event.amount, currency: currency, memo: event.memo, from: playerParty, to: nil, adventure: adventure, source: source, origin: origin)
            }
            return try record(kind: .transfer, amount: event.amount, currency: currency, memo: event.memo, from: playerParty, to: other, adventure: adventure, source: source, origin: origin)
        }
    }
}
