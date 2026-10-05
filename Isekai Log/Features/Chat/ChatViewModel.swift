//
//  ChatViewModel.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import Observation
import SwiftData

/// Drives one adventure's chat: builds prompts, streams narrator turns, books money events.
@MainActor
@Observable
final class ChatViewModel {
    let adventure: Adventure
    private let modelContext: ModelContext
    private let settings: AppSettings
    private let promptBuilder = PromptBuilder()

    private(set) var engine: any NarratorEngine
    private(set) var availability: EngineAvailability = .available
    private(set) var isResponding = false
    private(set) var suggestedActions: [String] = []
    private(set) var lastError: NarratorError?
    private(set) var lastMetrics: TurnMetrics?
    var inputText = ""

    private var currentTask: Task<Void, Never>?

    var ledger: Ledger { Ledger(modelContext: modelContext) }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    init(adventure: Adventure, modelContext: ModelContext, settings: AppSettings, engine: (any NarratorEngine)? = nil) {
        self.adventure = adventure
        self.modelContext = modelContext
        self.settings = settings
        self.engine = engine ?? EngineFactory.makeEngine(for: adventure.engineMode, settings: settings)
    }

    // MARK: - Lifecycle

    func start() async {
        await refreshAvailability()
        if adventure.messages.isEmpty {
            await runTurn(playerInput: "(The adventure begins. Introduce the world, the hero's situation and their nearly empty purse.)", playerMessage: nil)
        } else {
            suggestedActions = adventure.sortedMessages.last { $0.role == .narrator }?.suggestedActions ?? []
            await engine.prewarm(instructions: makeRequest(playerInput: "").instructions)
        }
    }

    func refreshAvailability() async {
        availability = await engine.availability()
    }

    /// Switches between offline and online narrators without losing the log.
    func setMode(_ mode: EngineMode) {
        guard mode != adventure.engineMode || !availability.isAvailable else { return }
        cancel()
        adventure.engineMode = mode
        engine = EngineFactory.makeEngine(for: mode, settings: settings)
        addSystemNote(String(localized: "Switched to \(mode.title) mode."))
        save()
        Task { await refreshAvailability() }
    }

    // MARK: - Sending

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        inputText = ""
        send(text)
    }

    func send(_ text: String) {
        guard !isResponding else { return }
        let playerMessage = ChatMessage(role: .player, text: text, adventure: adventure)
        modelContext.insert(playerMessage)
        adventure.messages.append(playerMessage)
        suggestedActions = []
        save()
        currentTask = Task { await runTurn(playerInput: text, playerMessage: playerMessage) }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Turn

    private func runTurn(playerInput: String, playerMessage: ChatMessage?) async {
        isResponding = true
        lastError = nil
        defer { isResponding = false }

        let narratorMessage = ChatMessage(role: .narrator, text: "", adventure: adventure, isPending: true)
        modelContext.insert(narratorMessage)
        adventure.messages.append(narratorMessage)

        let request = makeRequest(playerInput: playerInput)
        do {
            for try await update in engine.respond(to: request) {
                switch update {
                case .partialNarration(let text):
                    narratorMessage.text = text
                case .completed(let turn, let metrics):
                    narratorMessage.text = turn.narration
                    narratorMessage.suggestedActions = turn.suggestedActions
                    narratorMessage.record(metrics)
                    suggestedActions = turn.suggestedActions
                    lastMetrics = metrics
                    book(turn.ledgerEvents, source: narratorMessage)
                }
            }
            narratorMessage.isPending = false
        } catch {
            let narratorError = (error as? NarratorError) ?? .other(error.localizedDescription)
            lastError = narratorError
            if narratorMessage.text.isEmpty {
                adventure.messages.removeAll { $0.id == narratorMessage.id }
                modelContext.delete(narratorMessage)
            } else {
                narratorMessage.isPending = false
            }
            if narratorError != .cancelled {
                addSystemNote(narratorError.localizedDescription, isError: true)
            }
            if case .unavailable = narratorError { await refreshAvailability() }
        }
        adventure.updatedAt = .now
        save()
    }

    private func book(_ events: [LedgerEvent], source: ChatMessage) {
        let outcome = ledger.apply(events, to: adventure, source: source, origin: .narrator)
        for transaction in outcome.applied {
            addSystemNote(Self.ledgerLine(for: transaction, playerParty: adventure.playerParty))
        }
        for rejection in outcome.rejected {
            addSystemNote(String(localized: "Ledger refused \(rejection.event.money.formatted()) for \"\(rejection.event.memo)\": \(rejection.reason)"), isError: true)
        }
    }

    static func ledgerLine(for transaction: LedgerTransaction, playerParty: Party?) -> String {
        guard let playerParty else { return transaction.memo }
        let signed = Money(amount: transaction.signedAmount(for: playerParty), currency: transaction.currency).formatted(signed: true)
        switch transaction.kind {
        case .income: return "\(signed) · \(transaction.memo)"
        case .expense: return "\(signed) · \(transaction.memo)"
        case .transfer:
            let other = transaction.toParty?.id == playerParty.id ? transaction.fromParty?.name : transaction.toParty?.name
            return "\(signed) · \(transaction.memo) (\(other ?? "?"))"
        }
    }

    // MARK: - Prompt

    func makeRequest(playerInput: String) -> TurnRequest {
        let ledger = ledger
        let parties = adventure.parties.map { party in
            PromptBuilder.PartyStatus(
                name: party.name,
                members: party.sortedMembers.map { "\($0.name) (\($0.role))" },
                balances: ledger.balances(of: party),
                isPlayerParty: party.isPlayerParty
            )
        }
        let history: [TurnHistoryItem] = adventure.sortedMessages.compactMap { message in
            guard !message.isPending, !message.text.isEmpty else { return nil }
            switch message.role {
            case .player: return TurnHistoryItem(role: .player, text: message.text)
            case .narrator: return TurnHistoryItem(role: .narrator, text: message.text)
            case .system: return nil
            }
        }
        // The player message for this turn is already in the log; keep it out of history so it is not sent twice.
        let trimmedHistory = history.last?.text == playerInput && history.last?.role == .player ? Array(history.dropLast()) : history

        return promptBuilder.makeRequest(PromptBuilder.Input(
            premise: adventure.premise,
            personaName: adventure.persona.name,
            personalityInstructions: adventure.personalityInstructions,
            parties: parties,
            summary: adventure.summary,
            history: trimmedHistory,
            playerInput: playerInput,
            temperature: settings.temperature,
            languageName: PromptBuilder.preferredLanguageName
        ))
    }

    // MARK: - Helpers

    private func addSystemNote(_ text: String, isError: Bool = false) {
        let note = ChatMessage(role: .system, text: text, adventure: adventure)
        note.errorText = isError ? text : nil
        modelContext.insert(note)
        adventure.messages.append(note)
    }

    private func save() {
        do { try modelContext.save() } catch { assertionFailure("Save failed: \(error)") }
    }
}
