//
//  Theme.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

/// Colors and reusable chrome for the "another world at dusk" look.
enum IsekaiTheme {
    static let skyTop = Color(red: 0.06, green: 0.04, blue: 0.18)
    static let skyMiddle = Color(red: 0.27, green: 0.12, blue: 0.47)
    static let skyBottom = Color(red: 0.05, green: 0.09, blue: 0.24)
    static let moon = Color(red: 0.98, green: 0.90, blue: 0.70)
    static let secondMoon = Color(red: 0.62, green: 0.75, blue: 1.0)
    static let gold = Color(red: 0.99, green: 0.76, blue: 0.33)
    static let magenta = Color(red: 0.93, green: 0.37, blue: 0.70)
    static let cyan = Color(red: 0.45, green: 0.86, blue: 0.95)

    static let playerBubble = LinearGradient(
        colors: [magenta, Color(red: 0.55, green: 0.30, blue: 0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let titleGradient = LinearGradient(
        colors: [gold, Color.white, cyan],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Serif for narration gives the log a storybook feel; rounded for chrome keeps it playful.
    static func narration(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func heading(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .rounded, weight: .bold)
    }
}

/// Twilight sky with two moons and a scattering of stars.
struct IsekaiBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [IsekaiTheme.skyTop, IsekaiTheme.skyMiddle, IsekaiTheme.skyBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { proxy in
                let size = proxy.size
                Circle()
                    .fill(IsekaiTheme.moon.opacity(0.9))
                    .frame(width: size.width * 0.28)
                    .blur(radius: 2)
                    .position(x: size.width * 0.78, y: size.height * 0.14)
                Circle()
                    .fill(IsekaiTheme.secondMoon.opacity(0.55))
                    .frame(width: size.width * 0.12)
                    .blur(radius: 1)
                    .position(x: size.width * 0.22, y: size.height * 0.08)
                ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(.white.opacity(star.opacity))
                        .frame(width: star.size, height: star.size)
                        .position(x: size.width * star.x, y: size.height * star.y)
                }
                Ellipse()
                    .fill(IsekaiTheme.magenta.opacity(0.18))
                    .frame(width: size.width * 1.4, height: size.height * 0.35)
                    .blur(radius: 60)
                    .position(x: size.width * 0.5, y: size.height * 0.95)
            }
        }
        .ignoresSafeArea()
    }

    private struct Star { let x: CGFloat; let y: CGFloat; let size: CGFloat; let opacity: Double }

    private static let stars: [Star] = {
        var generator = SeededGenerator(seed: 20261005)
        return (0..<46).map { _ in
            Star(
                x: CGFloat.random(in: 0...1, using: &generator),
                y: CGFloat.random(in: 0...0.6, using: &generator),
                size: CGFloat.random(in: 1.2...3.0, using: &generator),
                opacity: Double.random(in: 0.25...0.9, using: &generator)
            )
        }
    }()
}

/// Deterministic generator so the star field is identical on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// RPG "status window" chrome: glass with a thin golden rim.
struct StatusWindowStyle: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [IsekaiTheme.gold.opacity(0.75), IsekaiTheme.gold.opacity(0.15), IsekaiTheme.cyan.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func statusWindow(cornerRadius: CGFloat = 22) -> some View {
        modifier(StatusWindowStyle(cornerRadius: cornerRadius))
    }
}

/// Small capsule badge used for engine mode and ledger notes.
struct Badge: View {
    var text: String
    var systemImage: String
    var tint: Color = IsekaiTheme.gold

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
    }
}
