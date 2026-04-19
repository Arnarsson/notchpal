# NotchPal MVP

Technical spike to evaluate whether the MacBook notch is a viable surface for HEKLA agent status, notifications, and context-drop.

**This is not a product.** It's 2-3 days of code to answer one question: can we render dynamic content under the notch, expand it on interaction, keep it above fullscreen apps, and accept file drops — cleanly, without fighting macOS?

## Run it

```bash
brew install xcodegen
./Scripts/bootstrap.sh
open NotchPal.xcodeproj
# Cmd+R in Xcode
```

First launch will ask for Accessibility permission. Grant it for completeness; the spike works without it (hover tracking is local to the panel).

## Poke at it from LLDB

While the app is running, pause in Xcode and try:

```
expr import NotchPal
expr NotchPal.AgentStatus.shared.label = "Arkivar indexing 342 files"
expr NotchPal.AgentStatus.shared.state = .busy
```

The notch should update immediately. That is the entire "HEKLA integration" for the spike.

## What to verify manually

See the six success criteria in `PRD.md`. Print them out, tick them off.

## When to stop

When `FINDINGS.md` exists and answers: does this platform hold up under the weight of a future HEKLA surface, and if so, what are the five hardest remaining problems?

## Repo layout

See `CLAUDE.md`.
