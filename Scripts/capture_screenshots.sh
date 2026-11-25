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
# or all of it, website images included: bash Scripts/refresh_screenshots.sh
#
set -euo pipefail

BUNDLE="com.jpwilson.borkmarkr"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$ROOT/Marketing/captures}"
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
# Seed signed in: the seeded custom topic (Trail running) is only created for
# an account, and without it its borks read "Races" with no topic.
xcrun simctl launch "$SIM" "$BUNDLE" -seed -signedIn >/dev/null
sleep 5

# Card covers are real remote thumbnails (see `DebugSeed.Cover`), so a screen
# is laid out before it is finished: `AsyncImage` starts its fetch when the
# card appears and cross-fades in over 0.22s. Shooting on the layout catches
# cards mid-fade, and a half-faded cover in an App Store screenshot is
# indistinguishable from one that never loaded. SETTLE is the wait after the
# screen is up, on top of the wait for the launch itself.
LAUNCH_WAIT="${LAUNCH_WAIT:-4}"
SETTLE="${SETTLE:-3}"

shoot() { # shoot <name> <startingTab> [extra launch args...]
  local name="$1" tab="$2"; shift 2
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$SIM" defaults write "$BUNDLE" startingTab -string "$tab"
  xcrun simctl launch "$SIM" "$BUNDLE" "$@" >/dev/null
  sleep "$LAUNCH_WAIT"
  sleep "$SETTLE"
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" 2>/dev/null
  echo "  $name.png"
}

# ── DEBUG-only launch arguments (ScreenshotDefaults / DebugSeed) ──────────
#
#   -query "protein"      pre-fills the search field at the top of Browse
#   -scopes "topics,tags" pre-selects the scope chips under it
#   -topic fitness        opens Browse straight onto a topic page (hero band)
#   -add URL -quickFileChosen   the Quick File dial for URL, a topic chosen
#   -importSheet          the You tab with the import sheet up
#   -dumpShareCard PATH   writes the rendered topic share card to a PNG
#   -neutralCovers        draws every cover as its topic's clay, no thumbnails
#
# and, for the signed-out save limit (Core/SaveLimit.swift), whose surfaces
# appear only at particular library sizes:
#
#   -borks 15             seed exactly 15 live borks — the Library card at
#                         "5 saves left before you'll need a free account."
#   -borks 20             the limit: the card asks, and + raises the wall
#   -waiting 3            add 3 borks flagged as having arrived over the limit
#                         (needs -borks; produces the greyed cards + banner)
#   -signedOut            ignore any real session in the Keychain
#   -signedIn             fake a session, to confirm none of the limit shows
#
# None of these are parsed outside DEBUG, so no launch argument can put a
# shipped build into one of these states.

echo "Capturing to $OUT:"
# Every screen passes `-signedIn`. The seed is 50 borks, past the signed-out
# limit of 20, so signed out each capture carries "50 borks on this phone —
# sign up to keep saving." True, and a terrible first frame for a store
# listing. Signed in is equally true and is what the screens are for.
shoot library library -signedIn
# Each screen with creator thumbnails has a `-neutral` twin: the same launch
# with every cover drawn as its topic's clay. The website shows the Library
# pair cross-fading (Scripts/make_web_screenshots.py diffs the two to find the
# covers), and a neutral App Store set can be composed from the twins. A twin
# is shot straight after its original, before anything changes the store.
shoot library-neutral library -signedIn -neutralCovers
# The dial after a topic is chosen (1.4's Quick File). Showing it saves the
# link, so it comes after the Library shot; the title has no "protein" in
# it, so the search shot below is unchanged by it.
shoot dial    library -signedIn -add "https://www.tiktok.com/@kaylawalks/video/7299999" -quickFileChosen
shoot browse  browse  -signedIn -browseAxis topics
# The topic page is reachable only by tapping a tile, so `-topic` is the only
# reproducible way to capture it.
shoot topic   browse  -signedIn -topic fitness
shoot topic-neutral  browse -signedIn -topic fitness -neutralCovers
# Search lives at the top of Browse (and the Library); -query pre-fills it so
# the capture shows results rather than the topic grid.
shoot search  browse  -signedIn -query "protein"
shoot search-neutral browse -signedIn -query "protein" -neutralCovers
shoot scoped  browse  -signedIn -query "run" -scopes "tags"
shoot scoped-neutral browse -signedIn -query "run" -scopes "tags" -neutralCovers
shoot import  you     -signedIn -importSheet
shoot revisit revisit -signedIn
shoot you     you     -signedIn

echo "Now: venv/bin/python Scripts/make_screenshots.py"
