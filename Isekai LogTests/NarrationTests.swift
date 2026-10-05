//
//  NarrationTests.swift
//  Isekai LogTests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Isekai_Log

struct PromptBuilderTests {
    private func input(history: [TurnHistoryItem] = [], summary: String = "") -> PromptBuilder.Input {
        PromptBuilder.Input(
            premise: "A kingdom at the edge of the map.",
            personaName: "Aqualis",
            personalityInstructions: NarratorPersona.goddess.instructions,
            parties: [
                PromptBuilder.PartyStatus(name: "Dawnbreakers", members: ["Kyle (Hero)"], balances: [Money(amount: 12, currency: .gold), Money(amount: 5, currency: .silver)], isPlayerParty: true),
                PromptBuilder.PartyStatus(name: "Merchant Guild", members: [], balances: [Money(amount: 300, currency: .gold)], isPlayerParty: false),
            ],
            summary: summary,
            history: history,
            playerInput: "I enter the tavern.",
            temperature: 0.7,
            languageName: "Japanese"
        )
    }

    @Test func instructionsCarryPersonaRulesAndLanguage() {
        let request = PromptBuilder().makeRequest(input())
        #expect(request.instructions.contains("Aqualis"))
        #expect(request.instructions.contains("ledgerEvents"))
        #expect(request.instructions.contains("Write in Japanese"))
        #expect(request.instructions.contains("1 G (gold) = 10 S (silver)"))
    }

    @Test func worldStateIncludesTreasuryAndOldWorldConversion() {
        let request = PromptBuilder().makeRequest(input())
        #expect(request.worldState.contains("Dawnbreakers"))
        #expect(request.worldState.contains("12 G, 5 S"))
        #expect(request.worldState.contains("¥125,000"))
        #expect(request.worldState.contains("Other party \"Merchant Guild\""))
        #expect(request.prompt.contains("[Player's action]\nI enter the tavern."))
    }

    @Test func historyIsTrimmedToBudgetAndCompactPromptIsShorter() {
        let long = String(repeating: "The road winds on. ", count: 60)
        let history = (0..<12).map { index in
            TurnHistoryItem(role: index.isMultiple(of: 2) ? .narrator : .player, text: "\(index) \(long)")
        }
        let builder = PromptBuilder()
        let request = builder.makeRequest(input(history: history, summary: "You left the capital."))
        #expect(request.prompt.contains("Earlier: You left the capital."))
        #expect(request.compactPrompt.count < request.prompt.count)
        #expect(request.prompt.count < builder.historyBudget + 1_200)
        #expect(request.history.count == builder.recentTurns)
        // Most recent turn survives, oldest is dropped.
        #expect(request.prompt.contains("Player: 11 "))
        #expect(!request.prompt.contains("Narrator: 0 "))
    }
}

struct NaturalLanguageParserTests {
    @Test func detectsIncome() {
        let events = NaturalLanguageLedgerParser.heuristic("I sell the wolf pelts for 30 gold")
        #expect(events.count == 1)
        #expect(events.first?.kind == "income")
        #expect(events.first?.amount == 30)
        #expect(events.first?.currency == "G")
    }

    @Test func detectsExpenseInSilver() {
        let events = NaturalLanguageLedgerParser.heuristic("spent 20 silver on bread")
        #expect(events.first?.kind == "expense")
        #expect(events.first?.amount == 20)
        #expect(events.first?.currency == "S")
    }

    @Test func detectsTransferWithCounterparty() {
        let events = NaturalLanguageLedgerParser.heuristic("I gave 5 gold to Mira for the guild fee")
        #expect(events.first?.kind == "transfer")
        #expect(events.first?.counterparty == "Mira")
        #expect(events.first?.amount == 5)
    }

    @Test func ignoresSentencesWithoutMoney() {
        #expect(NaturalLanguageLedgerParser.heuristic("I look around the tavern").isEmpty)
        #expect(NaturalLanguageLedgerParser.heuristic("that costs 3000 yen back home").isEmpty)
    }

    @Test func coinsMeanGold() {
        let events = NaturalLanguageLedgerParser.heuristic("paid 12 coins for a room")
        #expect(events.first?.currency == "G")
        #expect(events.first?.kind == "expense")
    }
}

struct NarratorTurnCodingTests {
    @Test func decodesCloudJSON() throws {
        let json = """
        {"narration":"The merchant counts out coins.","ledgerEvents":[{"kind":"income","amount":30,"currency":"G","memo":"sold pelts","counterparty":""}],"suggestedActions":["Buy a potion","Rest"]}
        """
        let turn = try JSONDecoder().decode(NarratorTurn.self, from: Data(json.utf8))
        #expect(turn.narration == "The merchant counts out coins.")
        #expect(turn.ledgerEvents.first?.amount == 30)
        #expect(turn.ledgerEvents.first?.transactionKind == .income)
        #expect(turn.suggestedActions.count == 2)
    }

    @Test func schemaMatchesCodableShape() {
        let properties = NarratorTurnSchema.json["properties"] as? [String: Any]
        #expect(Set(properties?.keys.map { $0 } ?? []) == ["narration", "ledgerEvents", "suggestedActions"])
        #expect(NarratorTurnSchema.json["additionalProperties"] as? Bool == false)
    }
}

struct CloudRequestTests {
    private func request() -> TurnRequest {
        TurnRequest(
            instructions: "Be a narrator.",
            prompt: "full",
            compactPrompt: "compact",
            history: [
                TurnHistoryItem(role: .narrator, text: "Welcome."),
                TurnHistoryItem(role: .player, text: "Hi."),
                TurnHistoryItem(role: .narrator, text: "Hello."),
            ],
            worldState: "Treasury: 10 G",
            playerInput: "I sell pelts for 30 gold.",
            personaName: "Mira",
            temperature: 0.7
        )
    }

    @Test func opusRequestUsesStructuredOutputEffortAndFallbacks() throws {
        let body = CloudNarratorEngine.requestBody(for: request(), configuration: .init(model: .opus55, apiKey: "k"))
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["temperature"] == nil)
        let outputConfig = try #require(body["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] as? String == "low")
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let system = try #require(body["system"] as? [[String: Any]])
        #expect((system.first?["cache_control"] as? [String: String])?["type"] == "ephemeral")
    }

    @Test func messagesAlternateAndStartWithUser() throws {
        let body = CloudNarratorEngine.requestBody(for: request(), configuration: .init(model: .opus55, apiKey: "k"))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let roles = messages.compactMap { $0["role"] as? String }
        #expect(roles == ["user", "assistant", "user", "assistant", "user"])
        #expect((messages.last?["content"] as? String)?.contains("I sell pelts for 30 gold.") == true)
        #expect((messages.last?["content"] as? String)?.contains("Treasury: 10 G") == true)
    }

    @Test func haikuRequestOmitsEffortAndFallbacks() throws {
        let body = CloudNarratorEngine.requestBody(for: request(), configuration: .init(model: .haiku45, apiKey: "k"))
        #expect(body["fallbacks"] == nil)
        #expect(body["temperature"] as? Double == 0.7)
        let outputConfig = try #require(body["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] == nil)
    }

    @Test func decodesMessagesResponseAndMapsErrors() throws {
        let json = """
        {"id":"msg_1","model":"claude-opus-5-5","stop_reason":"end_turn","content":[{"type":"text","text":"{\\"narration\\":\\"x\\",\\"ledgerEvents\\":[],\\"suggestedActions\\":[]}"}],"usage":{"input_tokens":420,"output_tokens":55}}
        """
        let response = try JSONDecoder().decode(CloudNarratorEngine.MessagesResponse.self, from: Data(json.utf8))
        #expect(response.usage?.inputTokens == 420)
        #expect(response.content.first?.text?.contains("narration") == true)
        #expect(CloudNarratorEngine.error(forStatus: 401, data: Data()) == .unauthorized)
        #expect(CloudNarratorEngine.error(forStatus: 429, data: Data()) == .rateLimited)
        let bodyError = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}"#.utf8)
        #expect(CloudNarratorEngine.error(forStatus: 400, data: bodyError) == .network("bad"))
    }
}
