#!/usr/bin/env bash
# Capture every iOS screen a launch argument can reach, for design review.
#
#   Scripts/capture_design_review.sh <output-folder> [only-these-names...]
#
# File names follow the 1.3 baseline (`current/ios/NN-*.png` in the design
# review scratchpad), so each new shot sits beside the one it replaces; screens
# 1.3 could not reach get letter suffixes (01b, 03b…) or numbers from 26 up.
# Pass names (e.g. `01-library-top 02-browse`) to shoot only those.
#
# It builds a Debug app, makes its OWN temporary iPhone 17 Pro simulator
# (1206×2622, the baseline's size), shoots, and deletes the simulator again —
# so it never disturbs a simulator somebody else is using. KEEP_SIM=1 keeps
# it (its UDID is printed); SIM=<udid> reuses an existing one and leaves it.
#
# The launch arguments are DEBUG-only (App/ScreenshotDefaults.swift and the
# screens' own debug hooks); none is parsed in a shipped build. A shot whose
# consumer hasn't been wired yet simply shows the screen it launched on.
#
# Env: DD (derived data, default /tmp/bookmarker-design-review), WAIT (seconds
# per shot, default 6), SKIP_BUILD=1 (reuse the last build).
set -euo pipefail

OUT="${1:?usage: Scripts/capture_design_review.sh <output-folder> [names...]}"
shift
ONLY=("$@")
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="com.jpwilson.borkmarkr"
DD="${DD:-/tmp/bookmarker-design-review}"
WAIT="${WAIT:-6}"
APP="$DD/Build/Products/Debug-iphonesimulator/borkmarkr.app"
mkdir -p "$OUT"

# ── Simulator ────────────────────────────────────────────────────────────
OWN_SIM=0
if [ -z "${SIM:-}" ]; then
  RUNTIME="$(xcrun simctl list runtimes available | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+-[0-9]+$' | tail -1)"
  SIM="$(xcrun simctl create "bookmarker design review" "iPhone 17 Pro" "$RUNTIME")"
  OWN_SIM=1
fi
cleanup() {
  if [ "$OWN_SIM" = 1 ] && [ "${KEEP_SIM:-0}" != 1 ]; then
    xcrun simctl shutdown "$SIM" 2>/dev/null || true
    xcrun simctl delete "$SIM" 2>/dev/null || true
  elif [ "$OWN_SIM" = 1 ]; then
    echo "Kept simulator $SIM"
  fi
}
trap cleanup EXIT
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true
xcrun simctl ui "$SIM" appearance light 2>/dev/null || true
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true

# ── Build ────────────────────────────────────────────────────────────────
if [ "${SKIP_BUILD:-0}" != 1 ] || [ ! -d "$APP" ]; then
  echo "Building…"
  xcodebuild -project "$ROOT/borkmarkr.xcodeproj" -scheme borkmarkr \
    -destination "id=$SIM" -configuration Debug -derivedDataPath "$DD" \
    build CODE_SIGNING_ALLOWED=NO -quiet >/dev/null
fi

wanted() { # wanted <name>: true when no names were given, or this is one
  [ ${#ONLY[@]} -eq 0 ] && return 0
  local n; for n in "${ONLY[@]}"; do [ "$n" = "$1" ] && return 0; done; return 1
}

fresh() { # a clean install: DebugSeed only seeds an empty store
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$SIM" "$APP"
}

# shoot <name> <reset 0|1> <startingTab|-> [launch args...]
#   reset=1 reinstalls first (seed / empty-state shots); "-" leaves the tab.
shoot() {
  local name="$1" reset="$2" tab="$3"; shift 3
  wanted "$name" || return 0
  [ "$reset" = 1 ] && fresh
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  local args=("$@")
  if [ "$tab" != "-" ]; then args+=(-startingTab "$tab"); fi
  xcrun simctl launch "$SIM" "$BUNDLE" ${args[@]+"${args[@]}"} >/dev/null
  sleep "$WAIT"
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null 2>&1 && echo "  $name.png"
}

fresh
# Seed once up front, so a subset that skips 01 still has a library.
if ! wanted 01-library-top; then
  xcrun simctl launch "$SIM" "$BUNDLE" -seed -signedIn >/dev/null
  sleep "$WAIT"
fi
TIKTOK_NEW="https://www.tiktok.com/@kaylawalks/video/7299999"
TIKTOK_SEEDED="https://www.tiktok.com/@kaylawalks/video/7290001"

echo "Capturing to $OUT"
# Library
shoot 01-library-top              1 library -seed -signedIn
shoot 01b-library-rail            0 library -signedIn -libraryAt rail
shoot 01c-library-compact         0 library -signedIn -feedDensity compact -libraryAt rest
shoot 14-dial-hint                0 library -signedIn -dialHint
shoot 26-detail-sheet             0 library -signedIn -detail 0
shoot 29-toast                    0 library -signedIn -toast "Filed to Fitness"
# Browse, topics, sources, search, side quests
shoot 02-browse                   0 browse  -browseAxis topics
shoot 03-topic-fitness            0 browse  -topic fitness
shoot 03b-topic-unfiled           0 browse  -topic unfiled
shoot 03c-source-tiktok           0 browse  -source tiktok
shoot 15-search-protein           0 browse  -query protein
shoot 16-search-scoped-tags       0 browse  -query run -scopes tags
shoot 17-side-quests              0 browse  -browseAxis journeys
shoot 17b-new-quest               0 browse  -browseAxis journeys -newQuest
shoot 18-side-quest-detail        0 browse  -browseAxis journeys -openQuest -questBrief
# Revisit
shoot 04-revisit                  0 revisit -signedIn
shoot 04b-revisit-insights        0 revisit -signedIn -insights
shoot 04c-revisit-queue           0 revisit -signedIn -revisitQueue
# You
shoot 05-you-signed-in            0 you     -signedIn
shoot 06-you-signed-out           0 you     -signedOut
shoot 06b-you-import              0 you     -signedIn -importSheet
shoot 28-share-guide              0 you     -signedIn -shareGuide
shoot 27-sign-in                  0 library -signedOut -auth signIn
# Add sheet, picker, triage, share extension harness
shoot 07-add-paste-step           0 library -signedIn -add
shoot 08-add-quick-file-dial      0 library -signedIn -add "$TIKTOK_NEW"
shoot 08b-add-refine-panel        0 library -signedIn -add "$TIKTOK_NEW" -quickFileChosen
shoot 09-add-already-in-library   0 library -signedIn -add "$TIKTOK_SEEDED"
shoot 19-topic-picker             0 library -signedIn -add "$TIKTOK_NEW" -picker runn
shoot 10-triage-sort-your-borks   0 library -signedIn -triage
shoot 11-triage-check-our-guesses 0 library -signedIn -triage guesses
shoot 12-share-quick-file-harness 0 -       -quickFileShare "$TIKTOK_NEW"
shoot 12b-share-refine-panel      0 -       -quickFileShare "$TIKTOK_NEW" -quickFileChosen
# Sheets
shoot 13-pro-sheet                0 library -signedIn -proSheet
shoot 20-collections-list         0 library -signedIn -collections
shoot 25b-save-limit-wall         0 library -signedOut -wall
# Save-limit states (each reseeds a smaller library)
shoot 24-signed-out-15-borks      1 library -seed -borks 15 -signedOut
shoot 25-signed-out-at-limit-waiting 1 library -seed -borks 20 -waiting 3 -signedOut
# Empty states and first launch (no seed)
shoot 22-empty-library            1 library -hasOnboarded YES
shoot 23-empty-browse             0 browse  -hasOnboarded YES
shoot 21-first-launch-welcome     1 -
shoot 21b-onboarding-2            0 -       -onboardingPage 2
shoot 21c-onboarding-3            0 -       -onboardingPage 3
shoot 21d-onboarding-4            0 -       -onboardingPage 4
echo "Done."
