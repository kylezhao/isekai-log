//
//  AppSettings.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import Foundation
import Observation

/// User preferences. Small values live in UserDefaults; the API key lives in the keychain.
@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let defaultEngineMode = "defaultEngineMode"
        static let temperature = "temperature"
        static let cloudModel = "cloudModel"
        static let showMetrics = "showMetrics"
        static let apiKeyAccount = "anthropic-api-key"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    var defaultEngineMode: EngineMode {
        didSet { defaults.set(defaultEngineMode.rawValue, forKey: Keys.defaultEngineMode) }
    }

    /// Sampling temperature for the on-device model. Cloud models run with adaptive thinking at low effort.
    var temperature: Double {
        didSet { defaults.set(temperature, forKey: Keys.temperature) }
    }

    var cloudModel: CloudModel {
        didSet { defaults.set(cloudModel.rawValue, forKey: Keys.cloudModel) }
    }

    var showMetrics: Bool {
        didSet { defaults.set(showMetrics, forKey: Keys.showMetrics) }
    }

    var apiKey: String {
        didSet { keychain.set(apiKey, for: Keys.apiKeyAccount) }
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = .shared) {
        self.defaults = defaults
        self.keychain = keychain
        self.defaultEngineMode = defaults.string(forKey: Keys.defaultEngineMode).flatMap(EngineMode.init(rawValue:)) ?? .onDevice
        self.temperature = defaults.object(forKey: Keys.temperature) as? Double ?? 0.8
        self.cloudModel = defaults.string(forKey: Keys.cloudModel).flatMap(CloudModel.init(rawValue:)) ?? .default
        self.showMetrics = defaults.object(forKey: Keys.showMetrics) as? Bool ?? true
        self.apiKey = keychain.string(for: Keys.apiKeyAccount) ?? ""
    }
}

/// Builds the engine for a mode using the current settings.
enum EngineFactory {
    @MainActor
    static func makeEngine(for mode: EngineMode, settings: AppSettings) -> any NarratorEngine {
        switch mode {
        case .onDevice:
            return OnDeviceNarratorEngine()
        case .cloud:
            return CloudNarratorEngine(configuration: .init(model: settings.cloudModel, apiKey: settings.apiKey))
        case .scripted:
            return ScriptedNarratorEngine()
        }
    }
}
