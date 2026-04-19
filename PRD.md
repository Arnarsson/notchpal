# NotchPal MVP — Technical Spike PRD

## Purpose

Answer one question in 2-3 days: **Can we reliably render dynamic content in the MacBook notch, expand it on interaction, keep it above fullscreen apps, and accept dropped files — as a foundation for a future HEKLA notch surface?**

This is a throwaway spike. Code quality matters enough to not mislead future decisions, but no further. If the spike succeeds, it informs a real product PRD. If it fails, we learn why and stop.

## Strategic context

The standalone notch-utility market is occupied (NotchNook, commercial, Setapp-distributed, strong brand). A general-purpose open alternative is a goodwill-negative side project. The only version worth our time is a HEKLA client surface: a thin always-visible UI for agent status, notifications, and context-drop. This MVP proves the platform primitives for that future product — nothing more.

## Non-goals (explicit)

- No modules system, no widget framework, no preferences.
- No MediaRemote, no calendar, no battery, no media controls.
- No launch-at-login, no menu bar item beyond `Quit`.
- No signing, notarization, DMG, Sparkle.
- No CI, no tests beyond a single smoke test.
- No HEKLA integration. A `@Published` string stands in for agent state — wiring to the real HEKLA memory service happens post-spike if we proceed.

## Success criteria

1. Panel renders under the physical notch on a notched MacBook with correct geometry (uses `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea`) and correct bottom-corner masking.
2. Panel stays above fullscreen apps. Verified by: YouTube fullscreen in Safari, Xcode fullscreen, Keynote presenter mode.
3. Hover expands the panel with a spring animation; unhover collapses it. Respects Reduce Motion.
4. Dropping a file onto the collapsed notch triggers expansion and shows the file name/icon inside.
5. A `HeklaStatusView` renders a colored status dot + agent name + activity text, driven by an `@Observable AgentStatus` object that can be mutated from the debugger console. This proves the content pipeline.
6. No focus theft from the active app across 30 minutes of mixed use.
7. CPU under 2% at idle on M-series.

## Technical decisions (locked)

- **Window level:** `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))` — required to sit above fullscreen apps. `.statusBar` does not cut it and is wrong in the earlier draft.
- **Collection behavior:** `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
- **Main screen only.** `positionUnderNotch()` hard-guards against `NSScreen.main == nil` and does nothing on non-main screens. Secondary-display support is post-spike.
- **Notchless fallback:** synthetic 180x32pt rect at top-center of main screen. Same interaction model.
- **No DynamicNotchKit dependency in the spike.** We write the window ourselves (~60 lines) to understand the primitives before adopting a dependency. Adopting DynamicNotchKit post-spike is reasonable if it meets our needs; we want to know what it's doing for us first.
- **No SPM dependencies at all in v0.** Pure Foundation + AppKit + SwiftUI. Keeps the spike debuggable and the failure modes clearly ours.
- **Deployment target:** macOS 14.0+.
- **Activation policy:** `.accessory` (no Dock icon, no menu bar by default — we add a tiny `Quit` status item only).

## Architecture (minimal)

```
Sources/
  App/
    NotchPalApp.swift         // @main SwiftUI App
    AppDelegate.swift         // accessory activation, controller lifecycle, quit status item
  Window/
    NotchPanel.swift          // NSPanel subclass: transparent, screen-saver-level, masked
    NotchController.swift     // owns panel, positioning, show/hide, expand/collapse state
    NotchGeometry.swift       // pure functions: notch rect from NSScreen, fallback rect
  Interaction/
    HoverTracker.swift        // NSTrackingArea-based, debounced
    DragReceiver.swift        // NSDraggingDestination; emits dropped URLs
  Content/
    NotchRootView.swift       // top-level SwiftUI view; switches collapsed/expanded
    HeklaStatusView.swift     // placeholder agent-status UI
    AgentStatus.swift         // @Observable model; mutable from debugger
Scripts/
  bootstrap.sh                // xcodegen generate; open the project
project.yml                   // XcodeGen spec
```

No `Preferences/`, no `Modules/`, no `Resources/` beyond Info.plist and entitlements inline in `project.yml`.

## Milestones (compressed)

- **Day 1:** `NotchGeometry` + `NotchPanel` + `NotchController`. Hard-coded black rounded rect visible under the notch. Verified above fullscreen Safari+YouTube.
- **Day 2:** `HoverTracker` + expand/collapse spring. `HeklaStatusView` renders inside. Mutate `AgentStatus` from the debugger and watch the notch update.
- **Day 3:** `DragReceiver` + file-drop-triggers-expand. Manual smoke test pass against all six success criteria. Write findings doc.

## Findings doc (deliverable)

At the end of the spike, `FINDINGS.md` captures:

- What worked, what didn't, what surprised us.
- Whether DynamicNotchKit would have saved meaningful time (read their source, compare).
- Concrete answer: is this a platform worth building HEKLA surface on? Recommend yes/no/pivot.
- If yes: the 5 hardest problems that remain before a real product.

## Known hazards for the spike

- Accessibility permission is required for global hover monitoring. First-launch UX: prompt, then open System Settings if denied. Don't block the main thread.
- `screenSaverWindow` level plus `.fullScreenAuxiliary` behaves oddly when a fullscreen app has menu-bar auto-hide; test explicitly in Keynote presenter mode.
- Dropping files onto a tiny notch target is finicky. Expand the drag hit-test area to include a 40pt strip below the notch while collapsed; the user doesn't need to hit the 32pt notch exactly.
- `NSPanel` with `.nonactivatingPanel` is required to avoid focus theft. Verify in Xcode by dropping from Finder → panel must not steal focus from the active editor.
