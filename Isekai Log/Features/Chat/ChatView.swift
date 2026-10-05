//
//  ChatView.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @Environment(AppSettings.self) private var settings
    @State private var showingParty = false
    @State private var showingLedger = false
    @FocusState private var composerFocused: Bool

    init(adventure: Adventure, modelContext: ModelContext, settings: AppSettings) {
        _viewModel = State(initialValue: ChatViewModel(adventure: adventure, modelContext: modelContext, settings: settings))
    }

    private var adventure: Adventure { viewModel.adventure }

    var body: some View {
        ZStack {
            IsekaiBackground()
            VStack(spacing: 0) {
                StatusWindowView(viewModel: viewModel)
                    .padding(.horizontal)
                    .padding(.top, 6)
                messageList
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .navigationTitle(adventure.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingParty) {
            NavigationStack { PartyView(adventure: adventure) }
        }
        .sheet(isPresented: $showingLedger) {
            NavigationStack { LedgerView(adventure: adventure) }
        }
        .task { await viewModel.start() }
        .onDisappear { viewModel.cancel() }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if case .unavailable(let reason) = viewModel.availability {
                        AvailabilityBanner(reason: reason, currentMode: adventure.engineMode) { mode in
                            viewModel.setMode(mode)
                        }
                        .padding(.horizontal)
                    }
                    ForEach(adventure.sortedMessages) { message in
                        MessageBubbleView(message: message, showMetrics: settings.showMetrics)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: message.role == .player ? .trailing : .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 12)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: adventure.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: adventure.messages.count) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isResponding) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.suggestedActions) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: adventure.sortedMessages.last?.text.count ?? 0) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if !viewModel.suggestedActions.isEmpty, !viewModel.isResponding {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.suggestedActions, id: \.self) { action in
                            Button {
                                viewModel.send(action)
                            } label: {
                                Label(action, systemImage: "sparkle")
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(IsekaiTheme.gold)
                            .glassEffect(.regular.tint(IsekaiTheme.gold.opacity(0.15)).interactive(), in: .capsule)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("What do you do?", text: Bindable(viewModel).inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .accessibilityIdentifier("composerField")
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { viewModel.send() }
                    .padding(.horizontal, 6)

                if viewModel.isResponding {
                    Button {
                        viewModel.cancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(IsekaiTheme.magenta.opacity(0.8), in: Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        viewModel.send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(viewModel.canSend ? AnyShapeStyle(IsekaiTheme.playerBubble) : AnyShapeStyle(Color.secondary.opacity(0.3)), in: Circle())
                            .animation(.easeInOut(duration: 0.2), value: viewModel.canSend)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canSend)
                    .accessibilityIdentifier("sendButton")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.suggestedActions)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingParty = true } label: { Image(systemName: "person.3.fill") }
                .accessibilityLabel("Party")
                .accessibilityIdentifier("partyButton")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingLedger = true } label: { Image(systemName: "book.closed.fill") }
                .accessibilityLabel("Ledger")
                .accessibilityIdentifier("ledgerButton")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Narrator runs") {
                    ForEach(EngineMode.allCases) { mode in
                        Button {
                            viewModel.setMode(mode)
                        } label: {
                            Label {
                                Text(mode.title)
                                Text(mode.subtitle)
                            } icon: {
                                Image(systemName: mode == adventure.engineMode ? "checkmark.circle.fill" : mode.symbol)
                            }
                        }
                    }
                }
                ShareLink(item: TranscriptExporter.markdown(for: adventure, ledger: viewModel.ledger), preview: SharePreview(adventure.title)) {
                    Label("Export log as Markdown", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Availability banner

private struct AvailabilityBanner: View {
    let reason: String
    let currentMode: EngineMode
    let onSwitch: (EngineMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                ForEach(EngineMode.allCases.filter { $0 != currentMode }) { mode in
                    Button {
                        onSwitch(mode)
                    } label: {
                        Label(String(localized: "Use \(mode.title)"), systemImage: mode.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(IsekaiTheme.cyan.opacity(0.2)).interactive(), in: .capsule)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusWindow(cornerRadius: 18)
    }
}
