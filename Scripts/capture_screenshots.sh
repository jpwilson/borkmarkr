#!/usr/bin/env bash
# Capture App Store screenshots from the iPhone 17 Pro Max simulator.
#
# That simulator renders at exactly 1320x2868, which is the size App Store
# Connect wants for the 6.9" slot — so these are upload-ready with no resizing.
#
# Reproducible on purpose. Screenshots have to be retaken every time the UI
# changes, and "tap through the simulator and hope you land on the same state"
# is not a process you want to repeat under submission pressure. The library
# comes from DebugSeed, the per-screen state from ScreenshotDefaults.
#
#   Scripts/capture_screenshots.sh
#   venv/bin/python Scripts/make_screenshots.py
#
set -euo pipefail

BUNDLE="com.jpwilson.borkmarkr"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Marketing/captures"
DD="${DD:-$ROOT/.build/screenshots}"

SIM="${SIM:-$(xcrun simctl list devices available \
  | grep "iPhone 17 Pro Max" | head -1 | sed -E 's/.*\(([-0-9A-F]+)\).*/\1/')}"
[ -n "$SIM" ] || { echo "No iPhone 17 Pro Max simulator found."; exit 1; }

mkdir -p "$OUT"
xcrun simctl boot "$SIM" 2>/dev/null || true

xcodebuild -project "$ROOT/borkmarkr.xcodeproj" -scheme borkmarkr \
  -destination "id=$SIM" -configuration Debug -derivedDataPath "$DD" \
  build CODE_SIGNING_ALLOWED=NO >/dev/null

xcrun simctl install "$SIM" "$DD/Build/Products/Debug-iphonesimulator/borkmarkr.app"

# 9:41 and a full battery — the state Apple's own marketing shots use, and it
# keeps the captures identical run to run.
xcrun simctl status_bar "$SIM" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3

# Wipe first so DebugSeed actually seeds (it no-ops on a non-empty store).
xcrun simctl uninstall "$SIM" "$BUNDLE"
xcrun simctl install "$SIM" "$DD/Build/Products/Debug-iphonesimulator/borkmarkr.app"
xcrun simctl launch "$SIM" "$BUNDLE" -seed >/dev/null
sleep 5

shoot() { # shoot <name> <startingTab> [extra launch args...]
  local name="$1" tab="$2"; shift 2
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$SIM" defaults write "$BUNDLE" startingTab -string "$tab"
  xcrun simctl launch "$SIM" "$BUNDLE" "$@" >/dev/null
  sleep 4
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" 2>/dev/null
  echo "  $name.png"
}

echo "Capturing to Marketing/captures:"
shoot library library
shoot browse  browse
shoot search  search -query "protein"
shoot you     you

echo "Now: venv/bin/python Scripts/make_screenshots.py"
