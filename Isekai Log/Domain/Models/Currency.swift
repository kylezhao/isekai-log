//
//  Currency.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// A currency used in the adventure's world. Every rate is expressed against gold.
struct Currency: Identifiable, Hashable, Codable, Sendable {
    let code: String
    let name: String
    let symbol: String
    /// Value of one unit of this currency expressed in gold.
    let goldValue: Decimal
    /// Number of fraction digits shown when formatting.
    let fractionDigits: Int

    var id: String { code }

    static let gold = Currency(code: "G", name: "Gold", symbol: "G", goldValue: 1, fractionDigits: 2)
    static let silver = Currency(code: "S", name: "Silver", symbol: "S", goldValue: Decimal(string: "0.1")!, fractionDigits: 1)
    static let copper = Currency(code: "C", name: "Copper", symbol: "C", goldValue: Decimal(string: "0.01")!, fractionDigits: 0)
    /// The hero's old-world currency. Follows the isekai convention of 1 gold ≈ ¥10,000.
    static let yen = Currency(code: "JPY", name: "Yen", symbol: "¥", goldValue: Decimal(string: "0.0001")!, fractionDigits: 0)

    /// Currencies that circulate in the other world.
    static let inWorld: [Currency] = [.gold, .silver, .copper]
    /// Every currency the app knows about, including the old-world yen.
    static let all: [Currency] = inWorld + [.yen]

    /// Resolves a currency from a code, name or symbol, case-insensitively.
    static func resolve(_ token: String) -> Currency? {
        let needle = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return all.first { currency in
            currency.code.lowercased() == needle
                || currency.name.lowercased() == needle
                || currency.symbol.lowercased() == needle
                || (currency.name.lowercased() + "s") == needle
                || (needle == "yen" && currency == .yen)
        }
    }
}

enum CurrencyConverter {
    /// Converts an amount between two currencies using their gold values.
    static func convert(_ amount: Decimal, from source: Currency, to target: Currency) -> Decimal {
        guard source != target else { return amount }
        let inGold = amount * source.goldValue
        return inGold / target.goldValue
    }

    /// Human-readable exchange table handed to the narrator so prices stay consistent.
    static var exchangeTable: String {
        "1 G (gold) = 10 S (silver) = 100 C (copper). In the hero's old world 1 G is worth about ¥10,000."
    }
}

extension Decimal {
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// An amount paired with its currency.
struct Money: Hashable, Sendable {
    var amount: Decimal
    var currency: Currency

    func converted(to target: Currency) -> Money {
        Money(amount: CurrencyConverter.convert(amount, from: currency, to: target), currency: target)
    }

    func formatted(signed: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = currency.fractionDigits
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        let magnitude = formatter.string(from: NSDecimalNumber(decimal: amount.magnitude)) ?? "\(amount.magnitude)"
        let sign = amount < 0 ? "-" : (signed && amount > 0 ? "+" : "")
        if currency == .yen {
            return "\(sign)\(currency.symbol)\(magnitude)"
        }
        return "\(sign)\(magnitude) \(currency.symbol)"
    }
}
