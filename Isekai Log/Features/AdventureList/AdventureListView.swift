//
//  AdventureListView.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI

/// Home screen: saved adventures, plus entry points for a new adventure and settings.
struct AdventureListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Adventure.updatedAt, order: .reverse) private var adventures: [Adventure]

    @State private var path: [Adventure] = []
    @State private var showingNewAdventure = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                IsekaiBackground()
                if adventures.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Isekai Log")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewAdventure = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New adventure")
                        .accessibilityIdentifier("newAdventureButton")
                }
            }
            .navigationDestination(for: Adventure.self) { adventure in
                ChatView(adventure: adventure, modelContext: modelContext, settings: settings)
            }
            .sheet(isPresented: $showingNewAdventure) {
                NewAdventureView { adventure in
                    path = [adventure]
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(adventures) { adventure in
                    NavigationLink(value: adventure) {
                        AdventureCard(adventure: adventure)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            delete(adventure)
                        } label: {
                            Label("Delete adventure", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(IsekaiTheme.titleGradient)
            Text("You have been summoned.")
                .font(IsekaiTheme.heading(.title))
                .foregroundStyle(IsekaiTheme.titleGradient)
            Text("Start an adventure in another world. A narrator will tell your story and a ledger will keep honest books on every coin.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                showingNewAdventure = true
            } label: {
                Label("Begin a new life", systemImage: "wand.and.stars")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(IsekaiTheme.magenta)
        }
        .padding()
    }

    private func delete(_ adventure: Adventure) {
        modelContext.delete(adventure)
        try? modelContext.save()
    }
}

private struct AdventureCard: View {
    @Environment(\.modelContext) private var modelContext
    let adventure: Adventure

    var body: some View {
        let ledger = Ledger(modelContext: modelContext)
        let gold = adventure.playerParty.map { ledger.netWorthInGold(of: $0) } ?? 0
        HStack(spacing: 14) {
            Text(adventure.persona.emoji)
                .font(.system(size: 34))
                .frame(width: 54, height: 54)
                .glassEffect(.regular.tint(IsekaiTheme.magenta.opacity(0.2)), in: .circle)
            VStack(alignment: .leading, spacing: 5) {
                Text(adventure.title)
                    .font(IsekaiTheme.heading(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(adventure.sortedMessages.last(where: { $0.role == .narrator })?.text ?? adventure.premise)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Badge(text: adventure.engineMode.title, systemImage: adventure.engineMode.symbol, tint: IsekaiTheme.cyan)
                    Badge(text: Money(amount: gold.rounded(scale: 1), currency: .gold).formatted(), systemImage: "circle.hexagongrid.circle.fill")
                    Spacer()
                    Text(adventure.updatedAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .statusWindow()
    }
}
