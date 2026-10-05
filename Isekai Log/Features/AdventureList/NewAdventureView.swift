//
//  NewAdventureView.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI

/// Character creation: hero, world, narrator persona and where the narrator runs.
struct NewAdventureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let onCreate: (Adventure) -> Void

    @State private var title = ""
    @State private var heroName = ""
    @State private var heroRole = "Hero"
    @State private var heroEmoji = "🧑‍🚀"
    @State private var premiseID = WorldPremise.presets[0].id
    @State private var customPremise = ""
    @State private var personaID = NarratorPersona.goddess.id
    @State private var customInstructions = ""
    @State private var engineMode: EngineMode = .onDevice
    @State private var startingGold = 10

    private let heroEmojis = ["🧑‍🚀", "🧙", "🗡️", "🏹", "🛡️", "🧝", "🐉", "🍙"]
    private let heroRoles = ["Hero", "Mage", "Rogue", "Merchant", "Healer", "Summoner"]

    private var premise: String {
        premiseID == "custom" ? customPremise : (WorldPremise.presets.first { $0.id == premiseID }?.text ?? "")
    }

    private var canCreate: Bool {
        !heroName.trimmingCharacters(in: .whitespaces).isEmpty
            && !premise.trimmingCharacters(in: .whitespaces).isEmpty
            && (personaID != NarratorPersona.custom.id || !customInstructions.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IsekaiBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        heroSection
                        worldSection
                        personaSection
                        modeSection
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New Adventure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Begin") { create() }
                        .disabled(!canCreate)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("beginButton")
                }
            }
            .onAppear { engineMode = settings.defaultEngineMode }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var heroSection: some View {
        section(title: "Your hero", systemImage: "person.fill") {
            TextField("Hero name", text: $heroName)
                .textInputAutocapitalization(.words)
                .fieldStyle()
                .accessibilityIdentifier("heroNameField")
            TextField("Adventure title (optional)", text: $title)
                .fieldStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(heroEmojis, id: \.self) { emoji in
                        Button { heroEmoji = emoji } label: {
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(heroEmoji == emoji ? IsekaiTheme.gold.opacity(0.35) : .clear).interactive(), in: .circle)
                    }
                }
            }
            Picker("Class", selection: $heroRole) {
                ForEach(heroRoles, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(IsekaiTheme.gold)
            Stepper("Starting purse: \(startingGold) G", value: $startingGold, in: 0...500, step: 5)
                .font(.subheadline)
        }
    }

    private var worldSection: some View {
        section(title: "World", systemImage: "globe.asia.australia.fill") {
            ForEach(WorldPremise.presets) { preset in
                choiceRow(selected: premiseID == preset.id, emoji: preset.emoji, title: preset.title, subtitle: preset.text) {
                    premiseID = preset.id
                }
            }
            choiceRow(selected: premiseID == "custom", emoji: "✍️", title: String(localized: "Custom world"), subtitle: String(localized: "Describe your own setting.")) {
                premiseID = "custom"
            }
            if premiseID == "custom" {
                TextField("Describe the world and the hero's starting situation", text: $customPremise, axis: .vertical)
                    .lineLimit(3...6)
                    .fieldStyle()
            }
        }
    }

    private var personaSection: some View {
        section(title: "Narrator personality", systemImage: "theatermasks.fill") {
            Text("The personality becomes the model's instructions, so it shapes every turn.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(NarratorPersona.allChoices) { persona in
                choiceRow(selected: personaID == persona.id, emoji: persona.emoji, title: "\(persona.name) · \(persona.title)", subtitle: persona.tagline) {
                    personaID = persona.id
                }
            }
            if personaID == NarratorPersona.custom.id {
                TextField("Describe the narrator's voice, attitude and quirks", text: $customInstructions, axis: .vertical)
                    .lineLimit(3...6)
                    .fieldStyle()
            }
        }
    }

    private var modeSection: some View {
        section(title: "Narrator runs", systemImage: "cpu.fill") {
            ForEach(EngineMode.allCases) { mode in
                choiceRow(selected: engineMode == mode, systemImage: mode.symbol, title: mode.title, subtitle: mode.subtitle) {
                    engineMode = mode
                }
                .accessibilityIdentifier("mode-\(mode.rawValue)")
            }
            if engineMode == .cloud, !settings.hasAPIKey {
                Label("Add an Anthropic API key in Settings before playing online.", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(IsekaiTheme.magenta)
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(title: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(IsekaiTheme.heading(.headline))
                .foregroundStyle(IsekaiTheme.titleGradient)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow()
    }

    private func choiceRow(selected: Bool, emoji: String? = nil, systemImage: String? = nil, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let emoji { Text(emoji).font(.title2) }
                    if let systemImage { Image(systemName: systemImage).font(.title3).foregroundStyle(IsekaiTheme.cyan) }
                }
                .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? IsekaiTheme.gold : .secondary)
            }
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(selected ? IsekaiTheme.gold.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Create

    private func create() {
        let name = heroName.trimmingCharacters(in: .whitespaces)
        let adventureTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "\(name)'s Log") : title
        let adventure = Adventure(
            title: adventureTitle,
            premise: premise.trimmingCharacters(in: .whitespacesAndNewlines),
            personaID: personaID,
            customInstructions: customInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            engineMode: engineMode
        )
        modelContext.insert(adventure)

        let party = Party(name: String(localized: "\(name)'s Party"), isPlayerParty: true, adventure: adventure)
        modelContext.insert(party)
        adventure.parties.append(party)

        let hero = PartyMember(name: name, role: heroRole, emoji: heroEmoji, isPlayer: true, party: party)
        modelContext.insert(hero)
        party.members.append(hero)

        if startingGold > 0 {
            let ledger = Ledger(modelContext: modelContext)
            try? ledger.record(kind: .income, amount: Decimal(startingGold), currency: .gold, memo: String(localized: "Starting purse"), from: nil, to: party, adventure: adventure, source: nil, origin: .system)
        }
        try? modelContext.save()
        dismiss()
        onCreate(adventure)
    }
}

private extension View {
    func fieldStyle() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
