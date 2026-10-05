//
//  MessageBubbleView.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let showMetrics: Bool

    var body: some View {
        switch message.role {
        case .player: playerBubble
        case .narrator: narratorBubble
        case .system: systemNote
        }
    }

    private var playerBubble: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 56)
            Text(message.text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(IsekaiTheme.playerBubble, in: bubbleShape(isPlayer: true))
        }
        .padding(.horizontal)
    }

    private var narratorBubble: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if message.text.isEmpty, message.isPending {
                    TypingIndicator()
                } else {
                    Text(message.text)
                        .font(IsekaiTheme.narration())
                        .lineSpacing(3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .glassEffect(.regular, in: bubbleShape(isPlayer: false))
                }
                if showMetrics, !message.isPending, let engine = message.engineName {
                    metricsRow(engine: engine)
                        .padding(.leading, 6)
                }
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal)
    }

    private func metricsRow(engine: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: message.engineMode?.symbol ?? "cpu")
            Text(engine)
            if let latency = message.latencySeconds {
                Text("·")
                Text(String(format: "%.1fs", latency))
            }
            if let input = message.inputTokens, let output = message.outputTokens {
                Text("·")
                Text("\(input)→\(output) tok")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var systemNote: some View {
        HStack {
            Spacer()
            Label {
                Text(message.text)
            } icon: {
                Image(systemName: message.errorText == nil ? "coins" : "exclamationmark.triangle.fill")
            }
            .font(.caption.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(message.errorText == nil ? IsekaiTheme.gold : IsekaiTheme.magenta)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular.tint((message.errorText == nil ? IsekaiTheme.gold : IsekaiTheme.magenta).opacity(0.12)), in: .capsule)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func bubbleShape(isPlayer: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: 20,
            bottomLeading: isPlayer ? 20 : 6,
            bottomTrailing: isPlayer ? 6 : 20,
            topTrailing: 20
        ), style: .continuous)
    }
}

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(IsekaiTheme.gold.opacity(0.8))
                    .frame(width: 7, height: 7)
                    .offset(y: animating ? -5 : 0)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: UnevenRoundedRectangle(cornerRadii: .init(topLeading: 20, bottomLeading: 6, bottomTrailing: 20, topTrailing: 20), style: .continuous))
        .onAppear { animating = true }
    }
}
