#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen"
  exit 1
fi

xcodegen generate
echo
echo "Generated NotchPal.xcodeproj. Open it with:"
echo "  open NotchPal.xcodeproj"
