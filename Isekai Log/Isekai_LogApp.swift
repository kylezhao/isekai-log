//
//  Isekai_LogApp.swift
//  Isekai Log
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import SwiftData
import SwiftUI

@main
struct Isekai_LogApp: App {
    @State private var settings = AppSettings()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Adventure.self,
            Party.self,
            PartyMember.self,
            ChatMessage.self,
            LedgerTransaction.self,
        ])
        let isUITesting = CommandLine.arguments.contains("-ui-testing")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AdventureListView()
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(IsekaiTheme.gold)
        }
        .modelContainer(sharedModelContainer)
    }
}
