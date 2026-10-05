//
//  StatusWindowView.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

/// RPG-style status window: party, treasury and which narrator is running.
struct StatusWindowView: View {
    let viewModel: ChatViewModel

    private var adventure: Adventure { viewModel.adventure }
    private var party: Party? { adventure.playerParty }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(adventure.persona.emoji)
                    Text(party?.name ?? adventure.title)
                        .font(IsekaiTheme.heading(.headline))
                        .foregroundStyle(IsekaiTheme.titleGradient)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    ForEach(party?.sortedMembers ?? []) { member in
                        Text(member.emoji)
                            .font(.title3)
                            .accessibilityLabel(member.name)
                    }
                    if party?.members.isEmpty ?? true {
                        Text("No party members yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                treasury
                modeBadge
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .statusWindow()
    }

    private var treasury: some View {
        let ledger = viewModel.ledger
        let gold = party.map { ledger.netWorthInGold(of: $0) } ?? 0
        let yen = Money(amount: gold, currency: .gold).converted(to: .yen)
        return VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "circle.hexagongrid.circle.fill")
                    .foregroundStyle(IsekaiTheme.gold)
                Text(Money(amount: gold.rounded(scale: 2), currency: .gold).formatted())
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text("≈ \(yen.formatted()) back home")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .animation(.snappy, value: gold)
    }

    private var modeBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(viewModel.availability.isAvailable ? Color.green : IsekaiTheme.magenta)
                .frame(width: 6, height: 6)
            Image(systemName: adventure.engineMode.symbol)
            Text(adventure.engineMode.title)
            if let latency = viewModel.lastMetrics?.latencySeconds {
                Text(String(format: "· %.1fs", latency))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(IsekaiTheme.cyan)
        .lineLimit(1)
        .fixedSize()
    }
}
