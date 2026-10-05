# Isekai Log（異世界ログ）

> An LLM roleplay adventure chat framework for iOS. Your log of another world.

Isekai Log tracks off-world adventures as chat logs: a narrator model runs the
story while the backend keeps honest books on gold, items, parties and trades.

Built for the Metanomaly iOS programming assignment (LLM Roleplay Adventure
Chat Framework).

## Status

Skeleton only. This is the stock Xcode SwiftUI + SwiftData template with
naming and file headers set up. Feature work has not started yet.

## Planned features

- Roleplay adventure chat framework built from scratch
- Backend bookkeeping that supports transactions and parties
- Offline chat mode (on-device model) and online chat mode (cloud model)
- Bonus: income and expenses described in natural language
- Bonus: currency conversion

## Tech stack

- Swift 5, SwiftUI, SwiftData, Swift Testing
- iOS 26.5+, Xcode 26.6
- Localized in English, Simplified Chinese (简体中文) and Japanese (日本語):
  UI strings in `Localizable.xcstrings`, app display name in `InfoPlist.xcstrings`
- Planned: Foundation Models (offline mode), a cloud LLM API (online mode),
  SwiftData ledger for parties and transactions

## Getting started

```sh
open "Isekai Log.xcodeproj"
```

Select the `Isekai Log` scheme and run on a device or simulator.

## Project layout

```
Isekai Log/          App target (SwiftUI + SwiftData)
Isekai LogTests/     Unit tests (Swift Testing)
Isekai LogUITests/   UI tests (XCTest)
```

## License

Copyright © 2026 Kyle Zhao. All rights reserved.
