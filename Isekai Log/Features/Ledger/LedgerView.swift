//
//  LedgerView.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI

/// Guild ledger: balances, currency conversion, natural-language entry and the full transaction history.
struct LedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let adventure: Adventure

    @State private var entryText = ""
    @State private var isParsing = false
    @State private var entryNote: String?
    @State private var convertAmount = "1"
    @State private var convertFrom: Currency = .gold
    @State private var convertTo: Currency = .yen

    private var ledger: Ledger { Ledger(modelContext: modelContext) }

    var body: some View {
        ZStack {
            IsekaiBackground()
            ScrollView {
                VStack(spacing: 18) {
                    balancesCard
                    entryCard
                    converterCard
                    historyCard
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Guild Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Balances

    private var balancesCard: some View {
        let party = adventure.playerParty
        let balances = party.map { ledger.balances(of: $0) } ?? []
        let gold = party.map { ledger.netWorthInGold(of: $0) } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text(party?.name ?? adventure.title)
                .font(IsekaiTheme.heading(.title3))
                .foregroundStyle(IsekaiTheme.titleGradient)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ForEach(Currency.inWorld) { currency in
                    let amount = balances.first { $0.currency == currency }?.amount ?? 0
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currency.name).font(.caption2).foregroundStyle(.secondary)
                        Text(Money(amount: amount, currency: currency).formatted())
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                    if currency != Currency.inWorld.last { Spacer() }
                }
            }
            Divider().overlay(IsekaiTheme.gold.opacity(0.3))
            HStack {
                Label("Net worth", systemImage: "circle.hexagongrid.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(IsekaiTheme.gold)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Money(amount: gold.rounded(scale: 2), currency: .gold).formatted()).font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("≈ \(Money(amount: gold, currency: .gold).converted(to: .yen).formatted()) in the old world")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow()
    }

    // MARK: - Natural-language entry

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Record in plain words", systemImage: "text.bubble.fill")
                .font(IsekaiTheme.heading(.headline))
                .foregroundStyle(IsekaiTheme.titleGradient)
            Text("Try “spent 20 silver on bread” or “gave 5 gold to Mira”. Parsed on-device when Apple Intelligence is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Describe a transaction", text: $entryText, axis: .vertical)
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .onSubmit { Task { await recordEntry() } }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button {
                    Task { await recordEntry() }
                } label: {
                    if isParsing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus").fontWeight(.bold)
                    }
                }
                .frame(width: 40, height: 40)
                .buttonStyle(.glassProminent)
                .tint(IsekaiTheme.magenta)
                .disabled(entryText.trimmingCharacters(in: .whitespaces).isEmpty || isParsing)
            }
            if let entryNote {
                Text(entryNote)
                    .font(.caption)
                    .foregroundStyle(IsekaiTheme.gold)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow()
    }

    private func recordEntry() async {
        let text = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isParsing = true
        defer { isParsing = false }
        let result = await NaturalLanguageLedgerParser.parse(text)
        guard !result.events.isEmpty else {
            withAnimation { entryNote = String(localized: "No money found in that sentence.") }
            return
        }
        let outcome = ledger.apply(result.events, to: adventure, source: nil, origin: .player)
        try? modelContext.save()
        var parts: [String] = []
        if !outcome.applied.isEmpty {
            let source = result.source == .onDeviceModel ? String(localized: "on-device model") : String(localized: "keyword parser")
            parts.append(String(localized: "Recorded \(outcome.applied.count) via \(source)."))
        }
        parts.append(contentsOf: outcome.rejected.map { "\($0.event.money.formatted()): \($0.reason)" })
        withAnimation { entryNote = parts.joined(separator: " ") }
        entryText = ""
    }

    // MARK: - Converter

    private var converterCard: some View {
        let amount = Decimal(string: convertAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
        let converted = Money(amount: amount, currency: convertFrom).converted(to: convertTo)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Exchange", systemImage: "arrow.left.arrow.right.circle.fill")
                .font(IsekaiTheme.heading(.headline))
                .foregroundStyle(IsekaiTheme.titleGradient)
            TextField("Amount", text: $convertAmount)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 10) {
                Picker("From", selection: $convertFrom) {
                    ForEach(Currency.all) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .tint(IsekaiTheme.gold)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Picker("To", selection: $convertTo) {
                    ForEach(Currency.all) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .tint(IsekaiTheme.gold)
                Spacer()
                Text(converted.formatted())
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: converted)
            }
            Text(CurrencyConverter.exchangeTable)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow()
    }

    // MARK: - History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("History", systemImage: "list.bullet.rectangle.fill")
                .font(IsekaiTheme.heading(.headline))
                .foregroundStyle(IsekaiTheme.titleGradient)
            if adventure.transactions.isEmpty {
                Text("No transactions yet. Coins will appear here as the story unfolds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(adventure.sortedTransactions) { transaction in
                transactionRow(transaction)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow()
    }

    private func transactionRow(_ transaction: LedgerTransaction) -> some View {
        let player = adventure.playerParty
        let signed = player.map { transaction.signedAmount(for: $0) } ?? transaction.amount
        let isPositive = signed > 0
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: transaction))
                .foregroundStyle(isPositive ? Color.green : IsekaiTheme.magenta)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.memo.isEmpty ? transaction.kind.rawValue.capitalized : transaction.memo)
                    .font(.subheadline)
                HStack(spacing: 4) {
                    Text(transaction.fromParty?.name ?? String(localized: "World"))
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(transaction.toParty?.name ?? String(localized: "World"))
                    Text("· \(transaction.origin.rawValue)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money(amount: signed, currency: transaction.currency).formatted(signed: true))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isPositive ? Color.green : .primary)
                Text(transaction.createdAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func icon(for transaction: LedgerTransaction) -> String {
        switch transaction.kind {
        case .income: "arrow.down.circle.fill"
        case .expense: "arrow.up.circle.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        }
    }
}
