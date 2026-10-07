//
//  PlaytestRecorderTests.swift
//  Isekai LogTests
//
//  Created by Kyle Zhao on 2026-10-07.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Isekai_Log

/// Plays scripted sessions against the real on-device narrator and writes each log as Markdown to
/// `/tmp/isekai-playtests`, so the submission's playtest cases come from the actual model. Passes
/// vacuously when Apple Intelligence is unavailable.
@MainActor
struct PlaytestRecorderTests {
    struct Scenario {
        let name: String
        let persona: NarratorPersona
        let premise: WorldPremise
        let hero: String
        let startingGold: Decimal
        let actions: [String]
    }

    static let scenarios: [Scenario] = [
        Scenario(
            name: "01-goddess-merchant-town",
            persona: .goddess, premise: WorldPremise.presets[0], hero: "Yui", startingGold: 10,
            actions: [
                "I sell the wolf pelts to the merchant for 30 gold.",
                "I buy a healing potion for 15 gold.",
                "I try to buy a castle for 1000 gold.",
                "I give 5 gold to the orphanage.",
                "I ask the innkeeper about work.",
            ]
        ),
        Scenario(
            name: "02-receptionist-guild-fees",
            persona: .receptionist, premise: WorldPremise.presets[2], hero: "Ren", startingGold: 50,
            actions: [
                "I register at the guild and pay the registration fee.",
                "I take the goblin bounty and head into the first floor.",
                "I sell the goblin ears I collected.",
                "I rent a room for the night.",
            ]
        ),
        Scenario(
            name: "03-demon-lord-temptation",
            persona: .demonLord, premise: WorldPremise.presets[1], hero: "Sora", startingGold: 20,
            actions: [
                "I haggle with the caravan master over the price of salt.",
                "I buy 10 silver worth of salt to resell.",
                "I accept the demon lord's shortcut and see what it costs.",
                "I check how much gold I have left.",
            ]
        ),
    ]

    @Test(.timeLimit(.minutes(20))) func recordsOnDevicePlaytests() async throws {
        let engine = OnDeviceNarratorEngine()
        guard case .available = await engine.availability() else {
            print("Playtest recorder: on-device model unavailable, skipping.")
            return
        }
        let directory = URL(fileURLWithPath: "/tmp/isekai-playtests", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for scenario in Self.scenarios {
            let schema = Schema([Adventure.self, Party.self, PartyMember.self, ChatMessage.self, LedgerTransaction.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let context = container.mainContext
            let adventure = Adventure(title: "\(scenario.hero)'s Log", premise: scenario.premise.text, personaID: scenario.persona.id, engineMode: .onDevice)
            context.insert(adventure)
            let party = Party(name: "\(scenario.hero)'s Party", isPlayerParty: true, adventure: adventure)
            context.insert(party); adventure.parties.append(party)
            let hero = PartyMember(name: scenario.hero, role: "Hero", emoji: "🧑‍🚀", isPlayer: true, party: party)
            context.insert(hero); party.members.append(hero)
            let ledger = Ledger(modelContext: context)
            try ledger.record(kind: .income, amount: scenario.startingGold, currency: .gold, memo: "Starting purse", from: nil, to: party, adventure: adventure, source: nil, origin: .system)

            let defaults = UserDefaults(suiteName: "IsekaiPlaytest-\(UUID().uuidString)")!
            let settings = AppSettings(defaults: defaults, keychain: KeychainStore(service: "com.kylezhao.Isekai-Log.tests"))
            let viewModel = ChatViewModel(adventure: adventure, modelContext: context, settings: settings, engine: engine)

            let clock = ContinuousClock()
            let started = clock.now
            await viewModel.start()
            for action in scenario.actions {
                viewModel.send(action)
                do {
                    try await waitUntilIdle(viewModel)
                } catch {
                    print("Playtest recorder: turn timed out for \"\(action)\" in \(scenario.name)")
                    viewModel.cancel()
                }
            }
            let elapsed = clock.now - started

            var markdown = TranscriptExporter.markdown(for: adventure, ledger: ledger)
            let narratorTurns = adventure.sortedMessages.filter { $0.role == .narrator }
            let latencies = narratorTurns.compactMap(\.latencySeconds)
            let tokensIn = narratorTurns.compactMap(\.inputTokens)
            let tokensOut = narratorTurns.compactMap(\.outputTokens)
            markdown += """


            ## Run metrics

            - Engine: \(narratorTurns.first?.engineName ?? "?") · \(narratorTurns.first?.modelID ?? "?")
            - Turns: \(narratorTurns.count), wall clock \(String(format: "%.1f", elapsed.components.seconds.magnitude > 0 ? Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18 : 0)) s
            - Latency per turn: min \(String(format: "%.2f", latencies.min() ?? 0)) s, mean \(String(format: "%.2f", latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count))) s, max \(String(format: "%.2f", latencies.max() ?? 0)) s
            - Tokens: input mean \(tokensIn.isEmpty ? 0 : tokensIn.reduce(0, +) / tokensIn.count), output mean \(tokensOut.isEmpty ? 0 : tokensOut.reduce(0, +) / tokensOut.count)
            - Ledger: \(adventure.transactions.count) transactions, final purse \(Money(amount: ledger.netWorthInGold(of: party), currency: .gold).formatted())
            - Refusals and errors: \(adventure.sortedMessages.filter { $0.role == .system && $0.errorText != nil }.count)
            - Recorded: \(Date.now.formatted(.iso8601)) on \(ProcessInfo.processInfo.operatingSystemVersionString) (\(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"))
            """
            try markdown.write(to: directory.appendingPathComponent("\(scenario.name).md"), atomically: true, encoding: .utf8)
            #expect(narratorTurns.count >= 2, "the session should contain narration in \(scenario.name)")
            print("Playtest recorder: \(scenario.name) narrator turns \(narratorTurns.count) of \(scenario.actions.count + 1)")
        }
    }

    private func waitUntilIdle(_ viewModel: ChatViewModel, timeout: Duration = .seconds(120)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while viewModel.isResponding || viewModel.adventure.sortedMessages.last?.isPending == true {
            try await Task.sleep(for: .milliseconds(100))
            if clock.now > deadline { throw CancellationError() }
        }
        try await Task.sleep(for: .milliseconds(150))
    }
}
