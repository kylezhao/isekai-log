//
//  NarratorEngine.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// Where the narrator's language model runs.
enum EngineMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Apple's on-device model via FoundationModels. Works offline.
    case onDevice
    /// Claude via the Anthropic Messages API. Needs network and an API key.
    case cloud
    /// Deterministic rule-based narrator for demos, previews and tests.
    case scripted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: String(localized: "On-device")
        case .cloud: String(localized: "Cloud")
        case .scripted: String(localized: "Scripted demo")
        }
    }

    var subtitle: String {
        switch self {
        case .onDevice: String(localized: "Apple Intelligence · works offline")
        case .cloud: String(localized: "Claude · needs network and an API key")
        case .scripted: String(localized: "Rule-based narrator, no model needed")
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: "iphone.gen3"
        case .cloud: "cloud.fill"
        case .scripted: "theatermasks.fill"
        }
    }

    var isOnline: Bool { self == .cloud }
}

/// Identifies the engine and model that produced a turn. Stored with each message for metrics.
struct EngineDescriptor: Hashable, Sendable {
    let mode: EngineMode
    let displayName: String
    let modelID: String
}

enum EngineAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool { self == .available }
}

struct TurnHistoryItem: Sendable, Equatable {
    enum Role: Sendable { case player, narrator }
    var role: Role
    var text: String
}

/// Everything an engine needs to produce one narrator turn. Built by `PromptBuilder`.
struct TurnRequest: Sendable {
    /// Persona, world rules and output contract. Goes into the model's instructions / system prompt.
    var instructions: String
    /// Full prompt: party status, recent story and the player's action.
    var prompt: String
    /// Shorter prompt used when the model reports the context window was exceeded.
    var compactPrompt: String
    /// Recent exchanges as a message list, for engines that take chat history separately.
    var history: [TurnHistoryItem]
    /// Rendered party status, for engines that send history and state separately.
    var worldState: String
    var playerInput: String
    var personaName: String
    var temperature: Double
}

struct TurnMetrics: Equatable, Sendable {
    var engine: EngineDescriptor
    var latency: Duration
    var inputTokens: Int?
    var outputTokens: Int?
    var retried: Bool

    var latencySeconds: Double {
        let parts = latency.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

enum TurnUpdate: Sendable {
    /// Narration text so far, for streaming engines.
    case partialNarration(String)
    case completed(NarratorTurn, TurnMetrics)
}

/// A narrator backend. Implementations: on-device, cloud and scripted.
protocol NarratorEngine: Sendable {
    var descriptor: EngineDescriptor { get }
    func availability() async -> EngineAvailability
    /// Lets the engine load its model ahead of the first turn.
    func prewarm(instructions: String) async
    func respond(to request: TurnRequest) -> AsyncThrowingStream<TurnUpdate, any Error>
}

enum NarratorError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case contextTooLong
    case guardrailViolation
    case refused(String)
    case rateLimited
    case unauthorized
    case missingAPIKey
    case network(String)
    case decoding(String)
    case emptyResponse
    case cancelled
    case other(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .contextTooLong: String(localized: "The story grew past the model's memory. Older events were condensed. Try again.")
        case .guardrailViolation: String(localized: "The narrator declined to describe that scene. Try a different action.")
        case .refused(let why): why.isEmpty ? String(localized: "The narrator refused this request.") : why
        case .rateLimited: String(localized: "The model is busy. Wait a moment and try again.")
        case .unauthorized: String(localized: "The API key was rejected. Check it in Settings.")
        case .missingAPIKey: String(localized: "Cloud mode needs an Anthropic API key. Add one in Settings.")
        case .network(let detail): detail
        case .decoding(let detail): String(localized: "The narrator's reply could not be read.") + " " + detail
        case .emptyResponse: String(localized: "The narrator fell silent. Try again.")
        case .cancelled: String(localized: "Cancelled.")
        case .other(let detail): detail
        }
    }
}
