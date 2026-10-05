//
//  Party.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData

/// A group that can hold money: the player's party, a guild, a merchant, a rival band.
@Model
final class Party {
    var id: UUID
    var adventureID: UUID
    var name: String
    var isPlayerParty: Bool
    var createdAt: Date

    var adventure: Adventure?

    @Relationship(deleteRule: .cascade, inverse: \PartyMember.party)
    var members: [PartyMember] = []

    @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.fromParty)
    var outgoing: [LedgerTransaction] = []

    @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.toParty)
    var incoming: [LedgerTransaction] = []

    init(name: String, isPlayerParty: Bool, adventure: Adventure) {
        self.id = UUID()
        self.adventureID = adventure.id
        self.name = name
        self.isPlayerParty = isPlayerParty
        self.createdAt = .now
        self.adventure = adventure
    }

    var sortedMembers: [PartyMember] {
        members.sorted { lhs, rhs in
            if lhs.isPlayer != rhs.isPlayer { return lhs.isPlayer }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

/// A character in a party.
@Model
final class PartyMember {
    var id: UUID
    var name: String
    /// Class or role, e.g. "Hero", "Mage", "Slime".
    var role: String
    /// Emoji used as a portrait.
    var emoji: String
    var isPlayer: Bool
    var createdAt: Date

    var party: Party?

    init(name: String, role: String, emoji: String, isPlayer: Bool, party: Party) {
        self.id = UUID()
        self.name = name
        self.role = role
        self.emoji = emoji
        self.isPlayer = isPlayer
        self.createdAt = .now
        self.party = party
    }
}
