//
//  PartyView.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI

/// Party roster and every other party the ledger knows about.
struct PartyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let adventure: Adventure

    @State private var newName = ""
    @State private var newRole = "Companion"
    @State private var newEmoji = "🐺"

    private let emojis = ["🐺", "🧚", "🤖", "🐉", "🧛", "🦊", "🧜", "👻"]

    var body: some View {
        ZStack {
            IsekaiBackground()
            ScrollView {
                VStack(spacing: 18) {
                    if let party = adventure.playerParty {
                        playerPartyCard(party)
                        addMemberCard(party)
                    }
                    if !adventure.otherParties.isEmpty {
                        otherPartiesCard
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Party")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private func playerPartyCard(_ party: Party) -> some View {
        let ledger = Ledger(modelContext: modelContext)
        return VStack(alignment: .leading, spacing: 12) {
            Text(party.name)
                .font(IsekaiTheme.heading(.title3))
                .foregroundStyle(IsekaiTheme.titleGradient)
            ForEach(party.sortedMembers) { member in
                HStack(spacing: 12) {
                    Text(member.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name).font(.subheadline.weight(.semibold))
                        Text(member.role).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if member.isPlayer {
                        Badge(text: String(localized: "You"), systemImage: "star.fill")
                    } else {
                        Button(role: .destructive) {
                            remove(member, from: party)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(IsekaiTheme.magenta)
                    }
                }
            }
            Divider().overlay(IsekaiTheme.gold.opacity(0.3))
            HStack {
                Label("Treasury", systemImage: "circle.hexagongrid.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IsekaiTheme.gold)
                Spacer()
                let balances = ledger.balances(of: party)
                Text(balances.isEmpty ? "0 G" : balances.map { $0.formatted() }.joined(separator: " · "))
                    .font(.subheadline.monospacedDigit())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow()
    }

    private func addMemberCard(_ party: Party) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recruit a companion", systemImage: "person.badge.plus")
                .font(IsekaiTheme.heading(.headline))
                .foregroundStyle(IsekaiTheme.titleGradient)
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField("Role", text: $newRole)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button { newEmoji = emoji } label: {
                            Text(emoji).font(.title2).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(newEmoji == emoji ? IsekaiTheme.gold.opacity(0.35) : .clear).interactive(), in: .circle)
                    }
                }
            }
            Button {
                add(to: party)
            } label: {
                Label("Add to party", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(IsekaiTheme.magenta)
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow()
    }

    private var otherPartiesCard: some View {
        let ledger = Ledger(modelContext: modelContext)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Other parties", systemImage: "building.columns.fill")
                .font(IsekaiTheme.heading(.headline))
                .foregroundStyle(IsekaiTheme.titleGradient)
            Text("Groups the ledger has traded with. They appear automatically when money changes hands.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(adventure.otherParties) { party in
                HStack {
                    Text(party.name).font(.subheadline)
                    Spacer()
                    let balances = ledger.balances(of: party)
                    Text(balances.isEmpty ? "0 G" : balances.map { $0.formatted() }.joined(separator: " · "))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow()
    }

    private func add(to party: Party) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let member = PartyMember(name: name, role: newRole.isEmpty ? "Companion" : newRole, emoji: newEmoji, isPlayer: false, party: party)
        modelContext.insert(member)
        party.members.append(member)
        adventure.updatedAt = .now
        try? modelContext.save()
        newName = ""
    }

    private func remove(_ member: PartyMember, from party: Party) {
        party.members.removeAll { $0.id == member.id }
        modelContext.delete(member)
        try? modelContext.save()
    }
}
