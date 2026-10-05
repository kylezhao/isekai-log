//
//  Isekai_LogUITests.swift
//  Isekai LogUITests
//
//  Created by Kyle Zhao on 2026-10-05.
//  Copyright © 2026 Kyle Zhao. All rights reserved.
//

import XCTest

/// Plays through a scripted adventure and saves screenshots to /tmp/isekai-screens for the showcase.
final class Isekai_LogUITests: XCTestCase {
    private let screenshotDirectory = URL(fileURLWithPath: "/tmp/isekai-screens", isDirectory: true)

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
    }

    @MainActor
    func testScriptedPlaythrough() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()
        snapshot(app, "01-home")

        app.buttons["newAdventureButton"].tap()
        let heroName = app.textFields["heroNameField"]
        XCTAssertTrue(heroName.waitForExistence(timeout: 5))
        heroName.tap()
        heroName.typeText("Kyle")
        snapshot(app, "02-new-adventure")

        let scriptedMode = app.buttons["mode-scripted"]
        var swipes = 0
        while !scriptedMode.isHittable, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(scriptedMode.waitForExistence(timeout: 5))
        scriptedMode.tap()
        snapshot(app, "03-new-adventure-mode")
        app.buttons["beginButton"].tap()

        let composer = textInput(app, "composerField")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        let opening = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Brightwater")).firstMatch
        XCTAssertTrue(opening.waitForExistence(timeout: 15), "Opening narration should mention Brightwater")
        snapshot(app, "04-chat-opening")

        composer.tap()
        composer.typeText("I sell the wolf pelts for 30 gold")
        app.buttons["sendButton"].tap()
        let ledgerNote = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "+30 G")).firstMatch
        XCTAssertTrue(ledgerNote.waitForExistence(timeout: 15), "Ledger note for +30 G should appear")
        snapshot(app, "05-chat-ledger-note")

        composer.tap()
        composer.typeText("I buy a castle for 1000 gold")
        app.buttons["sendButton"].tap()
        let refusal = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Ledger refused")).firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 15), "Overspending should be refused")
        snapshot(app, "06-chat-refusal")

        app.buttons["ledgerButton"].tap()
        let netWorth = app.staticTexts["Net worth"]
        XCTAssertTrue(netWorth.waitForExistence(timeout: 5))
        snapshot(app, "07-ledger")
        app.buttons["Done"].tap()

        app.buttons["partyButton"].tap()
        XCTAssertTrue(app.staticTexts["Treasury"].waitForExistence(timeout: 5))
        snapshot(app, "08-party")
        app.buttons["Done"].tap()
    }

    /// Plays one turn with the on-device model. Passes vacuously when Apple Intelligence is unavailable,
    /// so the suite stays green on machines without it while still exercising the real model where it exists.
    @MainActor
    func testOnDevicePlaythrough() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        app.buttons["newAdventureButton"].tap()
        let heroName = app.textFields["heroNameField"]
        XCTAssertTrue(heroName.waitForExistence(timeout: 5))
        heroName.tap()
        heroName.typeText("Yui")
        let onDeviceMode = app.buttons["mode-onDevice"]
        var swipes = 0
        while !onDeviceMode.isHittable, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        onDeviceMode.tap()
        app.buttons["beginButton"].tap()

        let composer = textInput(app, "composerField")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))

        // Either the opening narration arrives, or the availability banner explains why it cannot.
        let unavailable = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Apple Intelligence")).firstMatch
        let metrics = app.staticTexts.matching(NSPredicate(format: "label == %@", "Apple Intelligence")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        var narrated = false
        while Date() < deadline {
            if metrics.exists { narrated = true; break }
            if unavailable.exists, !metrics.exists, app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Use ")).firstMatch.exists {
                snapshot(app, "ondevice-unavailable")
                print("Isekai Log UI test: on-device model unavailable, skipping.")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if !narrated {
            snapshot(app, "ondevice-timeout")
            let labels = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
            XCTFail("On-device narrator did not produce the opening turn. Screen: \(labels.joined(separator: " | "))")
            return
        }
        snapshot(app, "09-ondevice-opening")

        composer.tap()
        composer.typeText("I sell the wolf pelts to the merchant for 30 gold")
        app.buttons["sendButton"].tap()
        let secondTurn = app.staticTexts.matching(NSPredicate(format: "label == %@", "Apple Intelligence"))
        let turnDeadline = Date().addingTimeInterval(180)
        while Date() < turnDeadline, secondTurn.count < 2 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertGreaterThanOrEqual(secondTurn.count, 2, "Second on-device turn should complete")
        snapshot(app, "10-ondevice-turn")

        app.buttons["ledgerButton"].tap()
        XCTAssertTrue(app.staticTexts["Net worth"].waitForExistence(timeout: 5))
        snapshot(app, "11-ondevice-ledger")
    }

    /// Multi-line SwiftUI text fields are exposed as text views.
    private func textInput(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let field = app.textFields[identifier]
        if field.exists { return field }
        return app.textViews[identifier]
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? screenshot.pngRepresentation.write(to: screenshotDirectory.appendingPathComponent("\(name).png"))
    }
}
