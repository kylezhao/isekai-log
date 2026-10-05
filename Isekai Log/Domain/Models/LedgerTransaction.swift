//
//  LedgerTransaction.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData

enum TransactionKind: String, Codable, CaseIterable, Sendable {
    /// Money enters a party from the world (loot, rewards, sales).
    case income
    /// Money leaves a party to the world (purchases, fees, bribes).
    case expense
    /// Money moves from one party to another.
    case transfer
}

enum TransactionOrigin: String, Codable, Sendable {
    /// Extracted from the narrator's structured turn.
    case narrator
    /// Entered by the player, including natural-language entries.
    case player
    /// Created by the app (starting funds, corrections).
    case system
}

/// A single movement of money. Balances are derived from these, never stored.
@Model
final class LedgerTransaction {
    var id: UUID
    var adventureID: UUID
    var createdAt: Date
    var kindRaw: String
    var amount: Decimal
    var currencyCode: String
    var memo: String
    var originRaw: String

    var adventure: Adventure?
    /// Party that paid. `nil` for income from the world.
    var fromParty: Party?
    /// Party that received. `nil` for expenses to the world.
    var toParty: Party?
    /// Narrator or player message that produced this transaction, if any.
    var sourceMessage: ChatMessage?

    init(
        kind: TransactionKind,
        amount: Decimal,
        currency: Currency,
        memo: String,
        origin: TransactionOrigin,
        adventure: Adventure,
        fromParty: Party?,
        toParty: Party?,
        sourceMessage: ChatMessage?
    ) {
        self.id = UUID()
        self.adventureID = adventure.id
        self.createdAt = .now
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currencyCode = currency.code
        self.memo = memo
        self.originRaw = origin.rawValue
        self.adventure = adventure
        self.fromParty = fromParty
        self.toParty = toParty
        self.sourceMessage = sourceMessage
    }

    var kind: TransactionKind { TransactionKind(rawValue: kindRaw) ?? .expense }
    var origin: TransactionOrigin { TransactionOrigin(rawValue: originRaw) ?? .system }
    var currency: Currency { Currency.resolve(currencyCode) ?? .gold }
    var money: Money { Money(amount: amount, currency: currency) }

    /// Signed amount from the point of view of a party: positive when it received, negative when it paid.
    func signedAmount(for party: Party) -> Decimal {
        if toParty?.id == party.id { return amount }
        if fromParty?.id == party.id { return -amount }
        return 0
    }
}
