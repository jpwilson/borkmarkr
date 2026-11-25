#!/usr/bin/env bash
# Retake the screenshots and rebuild everything made from them:
#
#   1. the simulator captures, `-neutral` twins included   (capture_screenshots.sh)
#   2. the App Store panels, 6.9" and 6.5", neutral covers  (make_screenshots.py)
#   3. the website's screenshots and live covers           (make_web_screenshots.py)
#   4. docs/llms-full.txt, which quotes the press images' sizes
#
#   bash Scripts/refresh_screenshots.sh
#
# SIM= and SETTLE= pass through to the capture script. The captures stay in
# Marketing/captures (not committed); look at the panels and docs/img before
# committing them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
CAPTURES="$ROOT/Marketing/captures"

OUT="$CAPTURES" bash "$ROOT/Scripts/capture_screenshots.sh"
SHOTS="$CAPTURES" OUT="$ROOT/Marketing/screenshots" NEUTRAL=1 "$PYTHON" "$ROOT/Scripts/make_screenshots.py"
SHOTS="$CAPTURES" DOCS="$ROOT/docs" "$PYTHON" "$ROOT/Scripts/make_web_screenshots.py"
"$PYTHON" "$ROOT/Scripts/gen_llms_full.py"
