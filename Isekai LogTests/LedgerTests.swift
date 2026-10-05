//
//  LedgerTests.swift
//  Isekai LogTests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import SwiftData
import Testing
@testable import Isekai_Log

@MainActor
struct LedgerTests {
    @Test func incomeIncreasesBalance() throws {
        let world = try TestWorld(startingGold: 10)
        let outcome = world.ledger.apply([LedgerEvent(kind: "income", amount: 30, currency: "G", memo: "sold pelts")], to: world.adventure, source: nil, origin: .narrator)
        #expect(outcome.applied.count == 1)
        #expect(outcome.rejected.isEmpty)
        #expect(world.ledger.balance(of: world.party, in: .gold) == 40)
    }

    @Test func expenseIsRejectedWhenFundsAreInsufficient() throws {
        let world = try TestWorld(startingGold: 10)
        let outcome = world.ledger.apply([LedgerEvent(kind: "expense", amount: 50, currency: "G", memo: "castle")], to: world.adventure, source: nil, origin: .narrator)
        #expect(outcome.applied.isEmpty)
        #expect(outcome.rejected.count == 1)
        #expect(outcome.rejected.first?.reason.contains("Not enough") == true)
        #expect(world.ledger.balance(of: world.party, in: .gold) == 10)
    }

    @Test func transferCreatesCounterpartyAndMovesMoney() throws {
        let world = try TestWorld(startingGold: 10)
        let outcome = world.ledger.apply([LedgerEvent(kind: "transfer", amount: 4, currency: "G", memo: "guild fee", counterparty: "Adventurers' Guild")], to: world.adventure, source: nil, origin: .narrator)
        #expect(outcome.applied.count == 1)
        let guild = try #require(world.ledger.party(named: "adventurers' guild", in: world.adventure, createIfMissing: false))
        #expect(guild.isPlayerParty == false)
        #expect(world.ledger.balance(of: guild, in: .gold) == 4)
        #expect(world.ledger.balance(of: world.party, in: .gold) == 6)
        #expect(world.adventure.otherParties.count == 1)
    }

    @Test func mixedBatchAppliesValidEventsAndReportsRejections() throws {
        let world = try TestWorld(startingGold: 10)
        let events = [
            LedgerEvent(kind: "income", amount: 30, currency: "G", memo: "bounty"),
            LedgerEvent(kind: "expense", amount: 100, currency: "G", memo: "too expensive"),
            LedgerEvent(kind: "expense", amount: 20, currency: "G", memo: "potion"),
            LedgerEvent(kind: "expense", amount: 0, currency: "G", memo: "free"),
        ]
        let outcome = world.ledger.apply(events, to: world.adventure, source: nil, origin: .narrator)
        #expect(outcome.applied.count == 2)
        #expect(outcome.rejected.count == 2)
        #expect(world.ledger.balance(of: world.party, in: .gold) == 20)
        #expect(world.adventure.transactions.count == 3) // starting purse + 2 applied
    }

    @Test func netWorthConvertsAcrossCurrencies() throws {
        let world = try TestWorld(startingGold: 1)
        _ = world.ledger.apply([
            LedgerEvent(kind: "income", amount: 5, currency: "S", memo: "tips"),
            LedgerEvent(kind: "income", amount: 50, currency: "C", memo: "coppers"),
        ], to: world.adventure, source: nil, origin: .player)
        #expect(world.ledger.netWorthInGold(of: world.party) == 2)
        #expect(world.ledger.balances(of: world.party).count == 3)
    }

    @Test func makesChangeFromGoldForSmallCopperPurchase() throws {
        let world = try TestWorld(startingGold: 8)
        let outcome = world.ledger.apply([LedgerEvent(kind: "expense", amount: 1, currency: "C", memo: "loaf of bread")], to: world.adventure, source: nil, origin: .narrator)
        #expect(outcome.applied.count == 1)
        #expect(outcome.rejected.isEmpty)
        // 0.01 G was changed into 1 C, which then paid for the bread.
        #expect(world.ledger.balance(of: world.party, in: .gold) == Decimal(string: "7.99"))
        #expect(world.ledger.balance(of: world.party, in: .copper) == 0)
        #expect(world.ledger.netWorthInGold(of: world.party) == Decimal(string: "7.99"))
        #expect(world.adventure.transactions.filter { $0.origin == .system }.count == 3) // purse + exchange pair
    }

    @Test func refusesWhenTotalPurseIsTooSmall() throws {
        let world = try TestWorld(startingGold: 1)
        let outcome = world.ledger.apply([LedgerEvent(kind: "expense", amount: 15, currency: "S", memo: "potion")], to: world.adventure, source: nil, origin: .narrator)
        #expect(outcome.applied.isEmpty)
        #expect(outcome.rejected.first?.reason.contains("has 1 G") == true)
        #expect(world.ledger.netWorthInGold(of: world.party) == 1)
    }

    @Test func unknownCurrencyIsRejected() throws {
        let world = try TestWorld(startingGold: 10)
        let outcome = world.ledger.apply([LedgerEvent(kind: "income", amount: 5, currency: "JPY", memo: "yen")], to: world.adventure, source: nil, origin: .player)
        #expect(outcome.applied.isEmpty)
        #expect(outcome.rejected.count == 1)
    }

    @Test func transactionsLinkToSourceMessage() throws {
        let world = try TestWorld(startingGold: 10)
        let message = ChatMessage(role: .narrator, text: "You sell the pelts.", adventure: world.adventure)
        world.context.insert(message)
        world.adventure.messages.append(message)
        let outcome = world.ledger.apply([LedgerEvent(kind: "income", amount: 3, currency: "G", memo: "pelts")], to: world.adventure, source: message, origin: .narrator)
        #expect(outcome.applied.first?.sourceMessage?.id == message.id)
        #expect(message.transactions.count == 1)
    }
}

struct CurrencyTests {
    @Test func goldToYenFollowsIsekaiRate() {
        #expect(CurrencyConverter.convert(1, from: .gold, to: .yen) == 10_000)
        #expect(CurrencyConverter.convert(10, from: .silver, to: .gold) == 1)
        #expect(CurrencyConverter.convert(1, from: .silver, to: .copper) == 10)
    }

    @Test func resolvesCodesNamesAndSymbols() {
        #expect(Currency.resolve("gold") == .gold)
        #expect(Currency.resolve("G") == .gold)
        #expect(Currency.resolve("silver") == .silver)
        #expect(Currency.resolve("¥") == .yen)
        #expect(Currency.resolve("doubloon") == nil)
    }

    @Test func formatsMoney() {
        #expect(Money(amount: 120, currency: .gold).formatted() == "120 G")
        #expect(Money(amount: 1_200_000, currency: .yen).formatted() == "¥1,200,000")
        #expect(Money(amount: 30, currency: .gold).formatted(signed: true) == "+30 G")
        #expect(Money(amount: -5, currency: .silver).formatted(signed: true) == "-5 S")
    }
}
