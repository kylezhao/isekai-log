//
//  SettingsView.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import FoundationModels
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var onDeviceStatus: EngineAvailability = .available

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Default for new adventures", selection: $settings.defaultEngineMode) {
                    ForEach(EngineMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                Toggle("Show model metrics under replies", isOn: $settings.showMetrics)
            } header: {
                Text("Narrator")
            }

            Section {
                HStack {
                    Label("Apple Intelligence", systemImage: "iphone.gen3")
                    Spacer()
                    switch onDeviceStatus {
                    case .available:
                        Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
                    case .unavailable:
                        Label("Unavailable", systemImage: "xmark.circle.fill").foregroundStyle(IsekaiTheme.magenta).labelStyle(.titleAndIcon)
                    }
                }
                if case .unavailable(let reason) = onDeviceStatus {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature: \(settings.temperature, specifier: "%.2f")")
                    Slider(value: $settings.temperature, in: 0...1.5, step: 0.05)
                    Text("Higher is more surprising. Applies to the on-device model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("On-device model")
            } footer: {
                Text("Context window: \(SystemLanguageModel.default.contextSize) tokens. Prompts are trimmed to fit.")
            }

            Section {
                Picker("Model", selection: $settings.cloudModel) {
                    ForEach(CloudModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                SecureField("Anthropic API key", text: $settings.apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if settings.hasAPIKey {
                    Label("Stored in the keychain on this device", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Cloud model")
            } footer: {
                Text("Online mode sends the persona, party status and recent story to the Anthropic Messages API with structured output. Opus 5.5 and Sonnet 5.5 run with adaptive thinking at low effort and server-side refusal fallbacks.")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Copyright © 2026 Kyle Zhao. All rights reserved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .scrollContentBackground(.hidden)
        .background(IsekaiBackground())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { onDeviceStatus = await OnDeviceNarratorEngine().availability() }
        .preferredColorScheme(.dark)
    }
}
