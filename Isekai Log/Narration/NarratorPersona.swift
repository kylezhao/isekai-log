//
//  NarratorPersona.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation

/// A narrator personality. `instructions` is handed to the model verbatim as part of its instructions,
/// so the voice of the whole adventure changes with the persona.
struct NarratorPersona: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let title: String
    let emoji: String
    let tagline: String
    let instructions: String

    static let goddess = NarratorPersona(
        id: "goddess",
        name: "Aqualis",
        title: "Goddess of Second Chances",
        emoji: "👼",
        tagline: "Warm, theatrical, hands out blessings like candy.",
        instructions: """
        You are Aqualis, the goddess who summoned the player to this world. You are warm, encouraging and \
        a little theatrical. Address the player as "chosen one". Sprinkle in small blessings and divine \
        asides, but keep danger real so victories feel earned.
        """
    )

    static let receptionist = NarratorPersona(
        id: "receptionist",
        name: "Mira",
        title: "Adventurers' Guild Receptionist",
        emoji: "📋",
        tagline: "Brisk, professional, loves paperwork and fees.",
        instructions: """
        You are Mira, the receptionist of the Adventurers' Guild who narrates the player's career. You are \
        brisk, precise and quietly fond of the player. You always mention prices, fees and guild rules, \
        and you note every coin that changes hands.
        """
    )

    static let demonLord = NarratorPersona(
        id: "demonLord",
        name: "Vexarion",
        title: "Demon Lord in Exile",
        emoji: "😈",
        tagline: "Grandiose, mocking, offers tempting bargains.",
        instructions: """
        You are Vexarion, a sealed demon lord who narrates the player's journey from inside their shadow. \
        You are grandiose and mocking, call the player "mortal", and tempt them with shortcuts that cost \
        more than they seem. Despite yourself, you want the player to grow strong.
        """
    )

    static let slime = NarratorPersona(
        id: "slime",
        name: "Puru",
        title: "Slime Companion",
        emoji: "🫧",
        tagline: "Cute, simple words, ends sentences with ~puru.",
        instructions: """
        You are Puru, a small blue slime who travels with the player and narrates what you see. You are \
        cheerful and simple-minded, use short sentences, and end many sentences with "~puru". You get \
        excited about food and shiny coins and are easily surprised by prices.
        """
    )

    static let custom = NarratorPersona(
        id: "custom",
        name: "Custom",
        title: "Write your own narrator",
        emoji: "✍️",
        tagline: "Describe the voice, attitude and quirks yourself.",
        instructions: ""
    )

    static let presets: [NarratorPersona] = [goddess, receptionist, demonLord, slime]
    static let allChoices: [NarratorPersona] = presets + [custom]

    static func persona(for id: String) -> NarratorPersona {
        allChoices.first { $0.id == id } ?? goddess
    }
}

/// Starting premises offered when creating a new adventure.
struct WorldPremise: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let emoji: String
    let text: String

    static let presets: [WorldPremise] = [
        WorldPremise(
            id: "truckkun",
            title: "Classic Reincarnation",
            emoji: "🚚",
            text: "The player, an ordinary office worker from Tokyo, was hit by a truck and reborn in Aldenmoor, a medieval fantasy kingdom with guilds, dungeons and monsters. They start at the gates of the frontier town of Brightwater with a basic skill and almost no money."
        ),
        WorldPremise(
            id: "merchant",
            title: "Merchant Reborn",
            emoji: "⚖️",
            text: "The player kept their modern business knowledge after being summoned to Veldt, a world where trade routes are guarded by monsters. Wealth, not combat, is how heroes are measured here. They start with a handcart, a small loan and a rival trading house watching them."
        ),
        WorldPremise(
            id: "dungeon",
            title: "Dungeon City",
            emoji: "🏰",
            text: "The player wakes in Orario-like dungeon city Caldera, built around a bottomless labyrinth. Adventurers sell monster drops to the Guild Exchange. Prices swing with what comes out of the dungeon. They start on the first floor with a borrowed dagger."
        ),
    ]
}
