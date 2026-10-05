//
//  CloudNarratorEngine.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// Cloud models offered for online mode.
enum CloudModel: String, CaseIterable, Identifiable, Sendable {
    case opus55 = "claude-opus-5-5"
    case sonnet55 = "claude-sonnet-5-5"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus55: "Claude Opus 5.5"
        case .sonnet55: "Claude Sonnet 5.5"
        case .haiku45: "Claude Haiku 4.5"
        }
    }

    /// Models that accept `output_config.effort` and the server-side `fallbacks` parameter.
    var supportsEffortAndFallbacks: Bool { self != .haiku45 }

    static let `default` = CloudModel.opus55
}

/// Online narrator that calls the Anthropic Messages API directly over HTTPS.
///
/// Structured output (`output_config.format`) guarantees the reply decodes as `NarratorTurn`. The persona
/// instructions are sent as a cached system block so repeated turns reuse the prompt cache.
final class CloudNarratorEngine: NarratorEngine {
    struct Configuration: Sendable {
        var model: CloudModel
        var apiKey: String
        /// Narration is a few sentences plus a handful of events, so a small cap is deliberate.
        var maxTokens: Int = 1_024
        var effort: String = "low"
        var endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!
    }

    let descriptor: EngineDescriptor
    private let configuration: Configuration
    private let session: URLSession

    init(configuration: Configuration, session: URLSession? = nil) {
        self.configuration = configuration
        self.descriptor = EngineDescriptor(mode: .cloud, displayName: "Claude", modelID: configuration.model.rawValue)
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 90
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    func availability() async -> EngineAvailability {
        configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .unavailable(reason: NarratorError.missingAPIKey.localizedDescription)
            : .available
    }

    func prewarm(instructions: String) async {}

    func respond(to request: TurnRequest) -> AsyncThrowingStream<TurnUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (turn, metrics) = try await self.generate(request)
                    continuation.yield(.completed(turn, metrics))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request

    func generate(_ request: TurnRequest) async throws -> (NarratorTurn, TurnMetrics) {
        guard case .available = await availability() else { throw NarratorError.missingAPIKey }

        let clock = ContinuousClock()
        let start = clock.now
        let body = try JSONSerialization.data(withJSONObject: Self.requestBody(for: request, configuration: configuration))

        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if configuration.model.supportsEffortAndFallbacks {
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw NarratorError.network("No HTTP response.") }
        guard (200...299).contains(http.statusCode) else {
            throw Self.error(forStatus: http.statusCode, data: data)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        if decoded.stopReason == "refusal" {
            throw NarratorError.refused(decoded.stopDetails?.explanation ?? "")
        }
        let text = decoded.content.compactMap { $0.text }.joined()
        guard !text.isEmpty else { throw NarratorError.emptyResponse }
        let turn: NarratorTurn
        do {
            turn = try JSONDecoder().decode(NarratorTurn.self, from: Data(text.utf8))
        } catch {
            throw NarratorError.decoding(decoded.stopReason == "max_tokens" ? "The reply was cut off." : error.localizedDescription)
        }

        let metrics = TurnMetrics(
            engine: EngineDescriptor(mode: .cloud, displayName: "Claude", modelID: decoded.model ?? configuration.model.rawValue),
            latency: clock.now - start,
            inputTokens: decoded.usage?.inputTokens,
            outputTokens: decoded.usage?.outputTokens,
            retried: false
        )
        return (turn, metrics)
    }

    /// Builds the Messages API body. Exposed for tests.
    static func requestBody(for request: TurnRequest, configuration: Configuration) -> [String: Any] {
        var messages: [[String: Any]] = []
        var lastRole: String?
        func append(role: String, text: String) {
            if lastRole == role, var last = messages.popLast() {
                last["content"] = ((last["content"] as? String) ?? "") + "\n\n" + text
                messages.append(last)
            } else {
                messages.append(["role": role, "content": text])
            }
            lastRole = role
        }
        if request.history.first?.role == .narrator {
            append(role: "user", text: "(The adventure begins.)")
        }
        for item in request.history {
            append(role: item.role == .player ? "user" : "assistant", text: item.text)
        }
        append(role: "user", text: """
        [Party status]
        \(request.worldState)

        [Player's action]
        \(request.playerInput)
        """)

        var outputConfig: [String: Any] = [
            "format": ["type": "json_schema", "schema": NarratorTurnSchema.json],
        ]
        var body: [String: Any] = [
            "model": configuration.model.rawValue,
            "max_tokens": configuration.maxTokens,
            "system": [[
                "type": "text",
                "text": request.instructions,
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": messages,
        ]
        if configuration.model.supportsEffortAndFallbacks {
            outputConfig["effort"] = configuration.effort
            body["fallbacks"] = "default"
        } else {
            body["temperature"] = request.temperature
        }
        body["output_config"] = outputConfig
        return body
    }

    // MARK: - Response

    struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheReadInputTokens: Int?
            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }
        }
        struct StopDetails: Decodable {
            let category: String?
            let explanation: String?
        }
        let model: String?
        let stopReason: String?
        let stopDetails: StopDetails?
        let content: [ContentBlock]
        let usage: Usage?
        enum CodingKeys: String, CodingKey {
            case model, content, usage
            case stopReason = "stop_reason"
            case stopDetails = "stop_details"
        }
    }

    struct APIErrorEnvelope: Decodable {
        struct APIError: Decodable {
            let type: String?
            let message: String?
        }
        let error: APIError?
    }

    static func error(forStatus status: Int, data: Data) -> NarratorError {
        let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error?.message
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        case 529: return .network(String(localized: "Claude is overloaded right now. Try again in a moment."))
        default: return .network(message ?? "HTTP \(status)")
        }
    }

    static func map(_ error: any Error) -> NarratorError {
        if error is CancellationError { return .cancelled }
        if let narratorError = error as? NarratorError { return narratorError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .network(String(localized: "You're offline. Switch to On-device mode to keep playing."))
            case .timedOut:
                return .network(String(localized: "The request timed out."))
            case .cancelled:
                return .cancelled
            default:
                return .network(urlError.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }
}
