# CLAUDE.md — NotchPal MVP spike

You are working on a 2-3 day technical spike. Read `PRD.md` first. This file tells you how to behave in this repo specifically.

## This is a spike, not a product

The deliverable is an honest answer to the question in PRD §Purpose, not a polished app. Aggressively reject scope that doesn't serve that question. If you find yourself reaching for a dependency, a preferences pane, a second module, or a test framework, stop and ask.

## Hard rules

1. **No new SPM dependencies** without explicit approval. The spike is pure AppKit + SwiftUI + Foundation.
2. **No new files outside the layout in PRD §Architecture.** If you think a file is needed, ask first.
3. **Main screen only.** `positionUnderNotch` must guard `guard let screen = NSScreen.main` and noop otherwise. No multi-display logic.
4. **Window level is `screenSaverWindow`.** Never `.statusBar` or `.floating`. If you find yourself changing this, something is wrong — ask.
5. **`.nonactivatingPanel` is mandatory** in the panel style mask. Focus theft is an instant-fail bug.
6. **Never force-unwrap** except in the smoke test.
7. **No persistence.** `AgentStatus` is in-memory only. No UserDefaults, no files.

## Coding conventions

Swift 5.9+, SwiftUI-first, AppKit where required (windowing, tracking areas, drag destinations). One type per file. `@Observable` macro for the status model. No Combine. Spring animations use `.spring(response: 0.4, dampingFraction: 0.75)` for content and `NSAnimationContext` for frame changes. Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — if true, swap spring for `.easeOut(duration: 0.1)`.

## Workflow

Before writing code for a task:

1. State the files you will create or modify.
2. State the specific acceptance check (from PRD success criteria) this task advances.
3. Write the code.
4. Report what you would manually test to verify it.

Do not run `xcodebuild` speculatively. The human builds in Xcode and pastes errors back.

## Debugging affordances

`AgentStatus` must be trivially mutable from LLDB:

```
expr AgentStatus.shared.label = "Arkivar indexing 342 files"
expr AgentStatus.shared.state = .busy
```

This is the entire "HEKLA integration" for the spike. Don't build an IPC layer, don't add a local HTTP server, don't parse HEKLA memory. A single global `@Observable` singleton is exactly enough.

## When in doubt

Ask. The human is Sven, he's running this spike to decide whether to invest more time, and the worst outcome is a spike that took a week and built the wrong thing.

## Forbidden until spike succeeds

MediaRemote, EventKit, IOKit, Sparkle, KeyboardShortcuts, DynamicNotchKit, SMAppService (launch-at-login), NSFilePromiseProvider (drag-out), any code-signing scripts, any DMG tooling, CI, GitHub Actions, unit tests beyond `SmokeTests.swift`, any reference to HEKLA's real codebase.
