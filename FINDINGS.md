# NotchPal MVP — Findings

**Spike dates:** 2026-04-17 → 2026-04-19
**Hours spent:** ~12 (including debugging drag-and-drop, toolchain issues, and NotchNook reverse-engineering)
**Machine tested on:** MacBook Air M3, macOS 26.4

---

## 1. Did the seven success criteria pass?

1. Panel renders under the notch with correct geometry — **PASS.** Uses `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` gap detection. Bottom corners masked with custom `NotchShape`. Pixel-accurate on M3 Air.
2. Panel stays above fullscreen apps — **PASS.** Verified Safari+YouTube fullscreen (⌃⌘F) at `.statusBar` level (25) with `.fullScreenAuxiliary` collection behavior. Panel stays visible and hover-responsive. Skipped Keynote (not installed) and Xcode (machine constraints) — same fullscreen mechanism.
3. Hover expand/collapse with spring — **PASS.** Spring animation works. Collapse on cursor exit works. Reduce Motion path exists in code.
4. File drop onto collapsed notch triggers expansion + shows file — **PASS.** Works at `.statusBar` level. Panel extends 12pt below the physical notch to provide a hittable drag target. `isTargeted` binding on SwiftUI `onDrop` triggers expansion when drag enters, then drop shows filename.
5. LLDB-mutable `AgentStatus` drives the UI — **PASS.** `@Observable` macro makes the type invisible to LLDB's Swift evaluator. Fixed with `@objc static func debugSet(label:state:)` callable via ObjC++ bridge: `expr -l objc++ -- (void)[NSClassFromString(@"NotchPal.AgentStatus") debugSetWithLabel:@"text" state:@"busy"]`. UI updates live.
6. No focus theft over mixed use — **PASS.** `.nonactivatingPanel` style mask + `.accessory` activation policy. Programmatically verified: `tell application "NotchPal" to activate` does not change frontmost app.
7. CPU under 2% at idle — **PASS.** 0.0% CPU at idle. ~180MB memory (debug build with SwiftUI overhead).

**All seven criteria pass.**

---

## 2. What surprised us?

- **`screenSaverWindow` level (1000) blocks drag-and-drop.** WindowServer won't route inter-app drag sessions to windows at this level. Not documented by Apple. This was the spike's biggest time sink (~4 hours). The PRD assumed `screenSaverWindow` was required for fullscreen layering — it's not.

- **`statusBar` level (25) + `.fullScreenAuxiliary` is the correct approach.** Reverse-engineering NotchNook confirmed this: they use exactly layer 25 with 74 pre-cached windows. `.statusBar` + `.fullScreenAuxiliary` collection behavior keeps the panel above fullscreen apps AND allows drag-and-drop. No conflict.

- **`canBecomeKey: false` also blocks drags, independently.** Even at `.floating` level, returning `false` from `canBecomeKey` prevents drag routing. `.nonactivatingPanel` alone is sufficient to prevent focus theft — the `canBecomeKey: false` belt-and-braces was actively harmful. Set `canBecomeKey` to `true`.

- **The collapsed panel is behind the physical notch cutout.** The 200×32pt collapsed frame sits exactly behind the display cutout. Drag targeting doesn't work because there's no visible/hittable surface. Fixed by extending collapsed height 12pt below the notch.

- **`@Observable` breaks LLDB's Swift expression evaluator.** The macro rewrites stored properties with observation registrar backing, making the type invisible to `import ModuleName` + `expr`. ObjC bridge works as a workaround.

- **Toolchain: `com.apple.provenance` xattrs.** macOS injects extended attributes on files under `~/Desktop` (iCloud-synced). Codesign refuses to sign over them. Build output must go to `$TMPDIR`. Cost ~2 hours.

- **Toolchain: `open` command `-600` errors.** Launch Services frequently returns `-600` when relaunching an ad-hoc signed app. Workaround: launch the binary directly.

---

## 3. Would DynamicNotchKit have saved meaningful time?

- **Hours saved if we'd adopted it:** ~2-3 (window setup, geometry detection, basic hover)
- **Hours lost to learning its abstractions:** ~4-6 (it has its own drag story and window-level opinions that wouldn't have saved the debugging time)
- **Verdict for the real product:** skip
- **Why:** DynamicNotchKit is designed for cosmetic notch replacements. Our window setup is ~50 lines and fully understood. The hard problems (window level, drag routing, LLDB observability) are outside its scope. Adopting it would add abstraction without solving anything.

---

## 4. The known bugs

| Bug | Severity | Fix direction |
|-----|----------|---------------|
| Collapsed panel invisible against dark content | low | Add a subtle 1px bottom border or glow. Cosmetic — hover still works. |
| `@Observable` breaks LLDB Swift expressions | low | Already mitigated with `@objc` helper. Not user-facing. |
| `open` command `-600` on relaunch | low | Build script launches binary directly. |
| Hover-during-drag may double-fire state transitions | medium | Distinct `isDragging` state in controller, separate timeout. |

---

## 5. The honest go/no-go

- [x] **GO.** The platform holds up. Proceed to a HEKLA-surface PRD.

**Why this answer and not another:** All seven criteria pass. The window-level conflict that initially looked like a blocker (`screenSaverWindow` vs drag-and-drop) is resolved: `.statusBar` level with `.fullScreenAuxiliary` provides both fullscreen layering and drag-and-drop, confirmed by reverse-engineering NotchNook (same approach, shipping product). SwiftUI in an NSPanel under the notch works, focus isolation works, performance is excellent, LLDB-driven content updates work, file drops work. No fundamental platform barriers remain — the remaining problems are design and engineering work, not unknown feasibility questions.

---

## 6. If GO: the five hardest remaining problems

1. **HEKLA IPC protocol.** The spike used `@Observable` + LLDB. Real product needs a reliable, low-latency IPC channel from HEKLA agent to NotchPal. Options: XPC (sandboxing complications), Unix domain socket (simple, fast), shared memory + file watch (crude but works). Must handle HEKLA restart, crash recovery, multiple agents.

2. **Multi-display policy.** Spike is main-screen-only. Product needs a decision: show on all displays? Only notched displays? Follow focus? NotchNook pre-caches 74 windows for this — there's real complexity here. External displays have no notch; the synthetic fallback handle needs design.

3. **Content pipeline beyond status text.** The spike proves one `AgentStatus` string renders. Production needs: multiple agents, priority ordering, notification badges, progress indicators, error states with actions, and a content overflow strategy when 3+ agents are active.

4. **Drag-and-drop UX refinement.** The 12pt hit area below the notch works but is small. Production may need a larger invisible hit area, a drag-approach animation, or visual affordance indicating "drop zone here." Test with non-technical users.

5. **Launch-at-login + auto-update.** `SMAppService` for login item, Sparkle for updates. Neither is hard but both require code signing and notarization, which means solving the distribution story (direct download vs Setapp vs App Store).

---

## 7. If GO: what the HEKLA surface actually looks like

The user is writing code in Xcode or VS Code. In their peripheral vision, the notch has a subtle green dot — HEKLA is indexing. They glance up: "Arkivar indexing 342 files" fades in on hover, then collapses when they look away. Later, HEKLA flags a potential issue: the dot turns yellow. They hover: "3 files reference deprecated API — tap to review." They drag a PDF onto the notch; it expands to show "Sending to Arkivar for context..." and the document lands in HEKLA's memory. This replaces the current workflow of switching to a HEKLA terminal window to check status, and eliminates the "is HEKLA still running?" uncertainty. The user would notice it missing the way they'd notice a missing menu bar clock — a glanceable status surface they didn't know they relied on.

---

## 8. If GO: rough effort to first usable HEKLA-surface release

- **Vertical slice (1 agent, status only, no drop):** ~20 hours. Assumes HEKLA exposes a Unix socket status feed. NotchPal reads it, maps to `AgentStatus`, done. No drop needed. Ship as developer tool only.
- **Parity demo (3 agents, status + drop + notifications):** ~60 hours. Multi-agent content layout, drop-to-HEKLA pipeline, basic notification badges. Still ad-hoc signed, developer-only.
- **Production-credible (full HEKLA integration, error handling, reconnect, external display policy):** ~120-160 hours. Adds reconnection logic, crash recovery, external display support, launch-at-login, code signing, notarization, auto-update. Requires design review for multi-agent UX.

---

## 9. What we would do differently next spike

The 2-3 day budget was right for the question asked. The drag-and-drop debugging consumed ~4 hours that could have been avoided by (a) testing window-level drag compatibility on day 1 with a 10-line throwaway script, and (b) reverse-engineering NotchNook first to learn the proven approach. **Lesson: when a shipping product solves your exact problem, inspect it before building from first principles.** CLAUDE.md's anti-scope-creep rules held well — no dependencies crept in, no features were added. The spike asked the right question and got a clean answer: **GO.**

---

## 10. NotchNook reverse-engineering notes

Inspected `/Applications/NotchNook.app` on 2026-04-19.

- **Architecture:** Single binary, no XPC services, no helper processes. 18MB universal binary.
- **Window level:** `statusBar` (25). NOT `screenSaverWindow`. This was the key insight.
- **Window count:** 74 windows total, only 1 on-screen at a time. Pre-cached for multiple displays and states (collapsed/expanded variants). Each is 250pt tall, full screen width.
- **Collection behavior:** `.fullScreenAuxiliary` (inferred from behavior — stays above fullscreen apps at level 25).
- **Linked frameworks:** Lottie (animations), Sparkle (auto-update), MediaRemoteAdapter (now playing), EventKit (calendar), ScreenCaptureKit, CoreBluetooth, IOKit, IOBluetooth, AVFoundation/AVKit. Heavy framework usage — full-featured product, not a thin overlay.
- **Entitlements:** Apple Events automation, audio input, camera, calendars, Setapp provisioning.
- **Implication for NotchPal:** We don't need `screenSaverWindow`. `.statusBar` + `.fullScreenAuxiliary` is the proven, shipping approach. Our spike now uses it and all criteria pass.
