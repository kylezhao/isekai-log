//
//  TranscriptExporter.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// Renders an adventure as Markdown so playtest logs can be shared and kept as test cases.
@MainActor
enum TranscriptExporter {
    static func markdown(for adventure: Adventure, ledger: Ledger) -> String {
        var lines: [String] = []
        lines.append("# \(adventure.title)")
        lines.append("")
        lines.append("- Narrator: \(adventure.persona.name) (\(adventure.persona.title))")
        lines.append("- Mode: \(adventure.engineMode.title)")
        lines.append("- Created: \(adventure.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("")
        lines.append("## Premise")
        lines.append("")
        lines.append(adventure.premise)
        lines.append("")
        lines.append("## Log")
        lines.append("")
        for message in adventure.sortedMessages {
            switch message.role {
            case .player:
                lines.append("**Player:** \(message.text)")
            case .narrator:
                var meta: [String] = []
                if let engine = message.engineName { meta.append(engine) }
                if let model = message.modelID { meta.append(model) }
                if let latency = message.latencySeconds { meta.append(String(format: "%.2fs", latency)) }
                if let input = message.inputTokens, let output = message.outputTokens { meta.append("\(input)→\(output) tok") }
                lines.append("**Narrator:** \(message.text)")
                if !meta.isEmpty { lines.append("  _\(meta.joined(separator: " · "))_") }
            case .system:
                lines.append("> \(message.text)")
            }
            lines.append("")
        }
        lines.append("## Ledger")
        lines.append("")
        lines.append("| When | Kind | Amount | From | To | Memo |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for transaction in adventure.sortedTransactions.reversed() {
            lines.append("| \(transaction.createdAt.formatted(date: .omitted, time: .shortened)) | \(transaction.kind.rawValue) | \(transaction.money.formatted()) | \(transaction.fromParty?.name ?? "world") | \(transaction.toParty?.name ?? "world") | \(transaction.memo) |")
        }
        lines.append("")
        for party in adventure.parties.sorted(by: { $0.isPlayerParty && !$1.isPlayerParty }) {
            let balances = ledger.balances(of: party).map { $0.formatted() }.joined(separator: ", ")
            lines.append("- \(party.name): \(balances.isEmpty ? "0 G" : balances)")
        }
        return lines.joined(separator: "\n")
    }
}
