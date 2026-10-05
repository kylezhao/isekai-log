//
//  TestSupport.swift
//  Isekai LogTests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData
@testable import Isekai_Log

/// In-memory SwiftData stack with one adventure and a player party holding `startingGold`.
@MainActor
struct TestWorld {
    let container: ModelContainer
    let context: ModelContext
    let adventure: Adventure
    let party: Party
    var ledger: Ledger { Ledger(modelContext: context) }

    init(startingGold: Decimal = 10, engineMode: EngineMode = .scripted) throws {
        let schema = Schema([Adventure.self, Party.self, PartyMember.self, ChatMessage.self, LedgerTransaction.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
        adventure = Adventure(title: "Test Run", premise: "A test world.", personaID: NarratorPersona.goddess.id, engineMode: engineMode)
        context.insert(adventure)
        party = Party(name: "Testers", isPlayerParty: true, adventure: adventure)
        context.insert(party)
        adventure.parties.append(party)
        let hero = PartyMember(name: "Kyle", role: "Hero", emoji: "🧑‍🚀", isPlayer: true, party: party)
        context.insert(hero)
        party.members.append(hero)
        if startingGold > 0 {
            try ledger.record(kind: .income, amount: startingGold, currency: .gold, memo: "Starting purse", from: nil, to: party, adventure: adventure, source: nil, origin: .system)
        }
        try context.save()
    }

    func settings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "IsekaiLogTests-\(UUID().uuidString)")!
        return AppSettings(defaults: defaults, keychain: KeychainStore(service: "com.kylezhao.Isekai-Log.tests"))
    }
}
