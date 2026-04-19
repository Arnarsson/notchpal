#!/usr/bin/env bash
# Regenerate project, build Debug, relaunch. Run from anywhere.
set -euo pipefail

cd "$(dirname "$0")/.."

for tool in xcodegen xcodebuild; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool not found." >&2
    echo "  xcodegen:  brew install xcodegen" >&2
    echo "  xcodebuild: install Xcode.app from the App Store, then 'sudo xcodebuild -license accept'" >&2
    exit 1
  fi
done

# Build outside the repo so iCloud Desktop sync / Spotlight can't inject
# xattrs into the .app bundle and break ad-hoc codesign.
DERIVED="${TMPDIR:-/tmp}/notchpal-build"

xcodegen generate

xcodebuild \
  -project NotchPal.xcodeproj \
  -scheme NotchPal \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  build

pkill -x NotchPal 2>/dev/null || true
open "$DERIVED/Build/Products/Debug/NotchPal.app"
