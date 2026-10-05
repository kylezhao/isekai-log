//
//  NarratorTurn.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import FoundationModels

/// The structured result of one narrator turn. Generated on-device with guided decoding
/// and decoded from JSON when the cloud model produces it.
@Generable(description: "A single narrator turn of a roleplay adventure.")
struct NarratorTurn: Codable, Equatable, Sendable {
    @Guide(description: "Narration for this turn: 2 to 5 vivid sentences in second person, in the narrator's voice. Plain prose only, no lists or JSON.")
    var narration: String

    @Guide(description: "Money that changed hands this turn. Leave empty when nothing was earned, spent or transferred.", .maximumCount(4))
    var ledgerEvents: [LedgerEvent]

    @Guide(description: "Up to three short next actions the player could take, each under eight words.", .maximumCount(3))
    var suggestedActions: [String]

    init(narration: String, ledgerEvents: [LedgerEvent] = [], suggestedActions: [String] = []) {
        self.narration = narration
        self.ledgerEvents = ledgerEvents
        self.suggestedActions = suggestedActions
    }
}

/// One money event reported by the narrator or parsed from the player's words.
@Generable(description: "One money event in the party ledger.")
struct LedgerEvent: Codable, Equatable, Sendable {
    @Guide(description: "income when the party gains money, expense when the party spends money, transfer when money moves from the party to another named party.", .anyOf(["income", "expense", "transfer"]))
    var kind: String

    @Guide(description: "Positive amount of money.")
    var amount: Decimal

    @Guide(description: "Currency code: G for gold, S for silver, C for copper.", .anyOf(["G", "S", "C"]))
    var currency: String

    @Guide(description: "Short memo such as 'sold wolf pelts' or 'night at the inn'.")
    var memo: String

    @Guide(description: "For transfers only: the name of the other party. Otherwise an empty string.")
    var counterparty: String

    init(kind: String, amount: Decimal, currency: String, memo: String, counterparty: String = "") {
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.memo = memo
        self.counterparty = counterparty
    }

    var transactionKind: TransactionKind {
        TransactionKind(rawValue: kind.lowercased()) ?? .expense
    }

    var resolvedCurrency: Currency {
        Currency.resolve(currency) ?? .gold
    }

    var money: Money { Money(amount: amount, currency: resolvedCurrency) }
}

/// JSON Schema for `NarratorTurn`, used for the cloud model's structured output.
enum NarratorTurnSchema {
    static let json: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["narration", "ledgerEvents", "suggestedActions"],
        "properties": [
            "narration": [
                "type": "string",
                "description": "Narration for this turn: 2 to 5 vivid sentences in second person, in the narrator's voice.",
            ],
            "ledgerEvents": [
                "type": "array",
                "description": "Money that changed hands this turn. Empty when nothing was earned, spent or transferred.",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["kind", "amount", "currency", "memo", "counterparty"],
                    "properties": [
                        "kind": ["type": "string", "enum": ["income", "expense", "transfer"]],
                        "amount": ["type": "number", "description": "Positive amount."],
                        "currency": ["type": "string", "enum": ["G", "S", "C"]],
                        "memo": ["type": "string"],
                        "counterparty": ["type": "string", "description": "Other party for transfers, else empty."],
                    ],
                ],
            ],
            "suggestedActions": [
                "type": "array",
                "description": "Up to three short next actions, each under eight words.",
                "items": ["type": "string"],
            ],
        ],
    ]
}
