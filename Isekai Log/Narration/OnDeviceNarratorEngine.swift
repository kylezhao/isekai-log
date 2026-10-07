//
//  OnDeviceNarratorEngine.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import FoundationModels

/// Offline narrator built on Apple's on-device model.
///
/// Each turn uses a fresh `LanguageModelSession` whose `instructions` carry the persona, and whose prompt
/// carries the party status and recent history. Keeping sessions stateless lets `PromptBuilder` control how
/// much history fits in the model's 4,096-token window instead of relying on the session transcript.
final class OnDeviceNarratorEngine: NarratorEngine {
    let descriptor = EngineDescriptor(
        mode: .onDevice,
        displayName: "Apple Intelligence",
        modelID: "SystemLanguageModel (on-device, ~3B)"
    )

    private let model: SystemLanguageModel
    /// Cap on generated tokens per turn: narration plus a few ledger events fit comfortably.
    private let maximumResponseTokens = 700

    init(model: SystemLanguageModel = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)) {
        self.model = model
    }

    func availability() async -> EngineAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: Self.describe(reason))
        }
    }

    func prewarm(instructions: String) async {
        guard model.isAvailable else { return }
        LanguageModelSession(model: model, instructions: instructions).prewarm()
    }

    func respond(to request: TurnRequest) -> AsyncThrowingStream<TurnUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (turn, metrics) = try await self.generate(request) { partial in
                        continuation.yield(.partialNarration(partial))
                    }
                    continuation.yield(.completed(turn, metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private func generate(
        _ request: TurnRequest,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> (NarratorTurn, TurnMetrics) {
        guard model.isAvailable else {
            let reason: String
            if case .unavailable(let why) = await availability() { reason = why } else { reason = "Unavailable" }
            throw NarratorError.unavailable(reason)
        }

        let clock = ContinuousClock()
        let start = clock.now
        let options = GenerationOptions(temperature: request.temperature, maximumResponseTokens: maximumResponseTokens)

        var retried = false
        var usedPrompt = request.prompt
        let turn: NarratorTurn
        do {
            turn = try await stream(prompt: usedPrompt, instructions: request.instructions, options: options, onPartial: onPartial)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            retried = true
            usedPrompt = request.compactPrompt
            turn = try await stream(prompt: usedPrompt, instructions: request.instructions, options: options, onPartial: onPartial)
        } catch LanguageModelSession.GenerationError.decodingFailure {
            // Rare: the model's output did not fit the schema. One more attempt with the compact prompt.
            retried = true
            usedPrompt = request.compactPrompt
            turn = try await stream(prompt: usedPrompt, instructions: request.instructions, options: options, onPartial: onPartial)
        }

        let latency = clock.now - start
        let inputTokens = try? await model.tokenCount(for: Instructions(request.instructions))
        let promptTokens = try? await model.tokenCount(for: usedPrompt)
        let outputTokens = try? await model.tokenCount(for: turn.narration)

        let metrics = TurnMetrics(
            engine: descriptor,
            latency: latency,
            inputTokens: (inputTokens ?? 0) + (promptTokens ?? 0),
            outputTokens: outputTokens,
            retried: retried
        )
        return (turn, metrics)
    }

    private func stream(
        prompt: String,
        instructions: String,
        options: GenerationOptions,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> NarratorTurn {
        let session = LanguageModelSession(model: model, instructions: instructions)
        let stream = session.streamResponse(to: prompt, generating: NarratorTurn.self, options: options)
        var lastContent: GeneratedContent?
        for try await snapshot in stream {
            lastContent = snapshot.rawContent
            if let narration = snapshot.content.narration, !narration.isEmpty {
                onPartial(narration)
            }
        }
        guard let lastContent else { throw NarratorError.emptyResponse }
        return try NarratorTurn(lastContent)
    }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            String(localized: "This device cannot run Apple Intelligence. Switch to Cloud mode.")
        case .appleIntelligenceNotEnabled:
            String(localized: "Turn on Apple Intelligence in Settings, or switch to Cloud mode.")
        case .modelNotReady:
            String(localized: "The on-device model is still downloading. Try again shortly.")
        @unknown default:
            String(localized: "The on-device model is unavailable.")
        }
    }

    static func map(_ error: any Error) -> NarratorError {
        if error is CancellationError { return .cancelled }
        if let narratorError = error as? NarratorError { return narratorError }
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .exceededContextWindowSize: return .contextTooLong
            case .guardrailViolation: return .guardrailViolation
            case .refusal: return .refused("")
            case .rateLimited: return .rateLimited
            case .concurrentRequests: return .other(String(localized: "The narrator is still answering the previous turn."))
            case .assetsUnavailable: return .unavailable(String(localized: "The on-device model assets are not available yet."))
            case .unsupportedLanguageOrLocale: return .other(String(localized: "The on-device model does not support this language."))
            case .decodingFailure: return .decoding(generationError.localizedDescription)
            case .unsupportedGuide: return .decoding(generationError.localizedDescription)
            @unknown default: return .other(generationError.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }
}
