//
//  PlaythroughTests.swift
//  Isekai LogTests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Isekai_Log

/// End-to-end turns through `ChatViewModel` with the deterministic scripted narrator.
/// These double as replayable playtest cases for the ledger pipeline.
@MainActor
struct PlaythroughTests {
    private func makeViewModel(_ world: TestWorld) -> ChatViewModel {
        ChatViewModel(adventure: world.adventure, modelContext: world.context, settings: world.settings(), engine: ScriptedNarratorEngine(wordDelay: .zero))
    }

    @Test func openingTurnIntroducesTheWorld() async throws {
        let world = try TestWorld()
        let viewModel = makeViewModel(world)
        await viewModel.start()
        let narrator = world.adventure.sortedMessages.filter { $0.role == .narrator }
        #expect(narrator.count == 1)
        #expect(narrator.first?.text.contains("Welcome") == true)
        #expect(narrator.first?.isPending == false)
        #expect(narrator.first?.engineName == "Scripted Demo")
        #expect((narrator.first?.latencySeconds ?? -1) >= 0)
        #expect(viewModel.suggestedActions.count == 3)
    }

    @Test func sellingBooksIncomeAndNotesIt() async throws {
        let world = try TestWorld(startingGold: 10)
        let viewModel = makeViewModel(world)
        await viewModel.start()
        viewModel.send("I sell the wolf pelts for 30 gold")
        try await waitUntilIdle(viewModel)
        #expect(world.ledger.balance(of: world.party, in: .gold) == 40)
        let notes = world.adventure.sortedMessages.filter { $0.role == .system }.map(\.text)
        #expect(notes.contains { $0.hasPrefix("+30 G") })
        let lastNarration = try #require(world.adventure.sortedMessages.last { $0.role == .narrator })
        #expect(lastNarration.transactions.count == 1)
    }

    @Test func overspendingIsRefusedByTheLedger() async throws {
        let world = try TestWorld(startingGold: 10)
        let viewModel = makeViewModel(world)
        await viewModel.start()
        viewModel.send("I buy a castle for 1000 gold")
        try await waitUntilIdle(viewModel)
        #expect(world.ledger.balance(of: world.party, in: .gold) == 10)
        let errors = world.adventure.sortedMessages.filter { $0.role == .system && $0.errorText != nil }
        #expect(errors.contains { $0.text.contains("Ledger refused") })
    }

    @Test func transfersCreateOtherParties() async throws {
        let world = try TestWorld(startingGold: 10)
        let viewModel = makeViewModel(world)
        await viewModel.start()
        viewModel.send("I give 4 gold to Mira")
        try await waitUntilIdle(viewModel)
        #expect(world.ledger.balance(of: world.party, in: .gold) == 6)
        let mira = try #require(world.adventure.otherParties.first)
        #expect(mira.name == "Mira")
        #expect(world.ledger.balance(of: mira, in: .gold) == 4)
    }

    @Test func switchingModeLeavesANoteAndKeepsTheLog() async throws {
        let world = try TestWorld()
        let viewModel = makeViewModel(world)
        await viewModel.start()
        let before = world.adventure.messages.count
        viewModel.setMode(.cloud)
        #expect(world.adventure.engineMode == .cloud)
        #expect(world.adventure.messages.count == before + 1)
        #expect(viewModel.engine.descriptor.mode == .cloud)
    }

    @Test func exportProducesMarkdownWithLedgerTable() async throws {
        let world = try TestWorld(startingGold: 10)
        let viewModel = makeViewModel(world)
        await viewModel.start()
        viewModel.send("I sell the wolf pelts for 30 gold")
        try await waitUntilIdle(viewModel)
        let markdown = TranscriptExporter.markdown(for: world.adventure, ledger: world.ledger)
        #expect(markdown.hasPrefix("# Test Run"))
        #expect(markdown.contains("**Player:** I sell the wolf pelts for 30 gold"))
        #expect(markdown.contains("| income | 30 G |"))
        #expect(markdown.contains("- Testers: 40 G"))
    }

    private func waitUntilIdle(_ viewModel: ChatViewModel, timeout: Duration = .seconds(5)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while viewModel.isResponding || viewModel.adventure.sortedMessages.last?.isPending == true {
            try await Task.sleep(for: .milliseconds(20))
            if clock.now > deadline { throw CancellationError() }
        }
        // Allow the turn task to finish bookkeeping after `isResponding` flips.
        try await Task.sleep(for: .milliseconds(50))
    }
}
