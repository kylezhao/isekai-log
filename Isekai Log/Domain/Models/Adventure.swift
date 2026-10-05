//
//  Adventure.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData

/// One campaign: a world, a narrator persona, a chat log and a ledger.
@Model
final class Adventure {
    var id: UUID
    var title: String
    /// The world premise the narrator builds on.
    var premise: String
    /// Identifier of a `NarratorPersona` preset, or `NarratorPersona.custom.id`.
    var personaID: String
    /// Free-text personality used when the persona is custom. Fed to the model's `instructions`.
    var customInstructions: String
    var engineModeRaw: String
    /// Rolling summary of older story beats, used to keep prompts inside the context window.
    var summary: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.adventure)
    var messages: [ChatMessage] = []

    @Relationship(deleteRule: .cascade, inverse: \Party.adventure)
    var parties: [Party] = []

    @Relationship(deleteRule: .cascade, inverse: \LedgerTransaction.adventure)
    var transactions: [LedgerTransaction] = []

    init(
        title: String,
        premise: String,
        personaID: String,
        customInstructions: String = "",
        engineMode: EngineMode
    ) {
        self.id = UUID()
        self.title = title
        self.premise = premise
        self.personaID = personaID
        self.customInstructions = customInstructions
        self.engineModeRaw = engineMode.rawValue
        self.summary = ""
        self.createdAt = .now
        self.updatedAt = .now
    }

    var engineMode: EngineMode {
        get { EngineMode(rawValue: engineModeRaw) ?? .onDevice }
        set { engineModeRaw = newValue.rawValue }
    }

    var persona: NarratorPersona {
        NarratorPersona.persona(for: personaID)
    }

    /// The personality text that goes into the model's instructions.
    var personalityInstructions: String {
        personaID == NarratorPersona.custom.id ? customInstructions : persona.instructions
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    var sortedTransactions: [LedgerTransaction] {
        transactions.sorted { $0.createdAt > $1.createdAt }
    }

    var playerParty: Party? {
        parties.first { $0.isPlayerParty }
    }

    var otherParties: [Party] {
        parties.filter { !$0.isPlayerParty }.sorted { $0.createdAt < $1.createdAt }
    }
}
