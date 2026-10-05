//
//  ChatMessage.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData

enum MessageRole: String, Codable, Sendable {
    case player
    case narrator
    /// Ledger notes, mode switches and errors shown inline in the log.
    case system
}

/// One entry in an adventure's chat log, including per-turn model metrics.
@Model
final class ChatMessage {
    var id: UUID
    var adventureID: UUID
    var roleRaw: String
    var text: String
    var createdAt: Date
    /// True while the narrator is still streaming this message.
    var isPending: Bool
    var errorText: String?
    var suggestedActions: [String]

    // Metrics for the turn that produced this message (narrator messages only).
    var engineModeRaw: String?
    var engineName: String?
    var modelID: String?
    var latencySeconds: Double?
    var inputTokens: Int?
    var outputTokens: Int?

    var adventure: Adventure?

    @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.sourceMessage)
    var transactions: [LedgerTransaction] = []

    init(role: MessageRole, text: String, adventure: Adventure, isPending: Bool = false) {
        self.id = UUID()
        self.adventureID = adventure.id
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = .now
        self.isPending = isPending
        self.errorText = nil
        self.suggestedActions = []
        self.adventure = adventure
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .system }
        set { roleRaw = newValue.rawValue }
    }

    var engineMode: EngineMode? {
        engineModeRaw.flatMap(EngineMode.init(rawValue:))
    }

    func record(_ metrics: TurnMetrics) {
        engineModeRaw = metrics.engine.mode.rawValue
        engineName = metrics.engine.displayName
        modelID = metrics.engine.modelID
        latencySeconds = metrics.latencySeconds
        inputTokens = metrics.inputTokens
        outputTokens = metrics.outputTokens
    }
}
