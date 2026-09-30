#!/usr/bin/env bash
set -euo pipefail
# Select an available iPhone rather than assuming one runner image/model name.
repair_device_id=$(xcrun simctl list devices available -j | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const devices = Object.values(JSON.parse(input).devices).flat();
  const phone = devices.find(d => d.name.startsWith("iPhone") && d.isAvailable);
  if (!phone) process.exit(1);
  process.stdout.write(phone.udid);
});')
xcodebuild -project borkmarkr.xcodeproj -scheme borkmarkr \
  -destination "id=$repair_device_id" -configuration Debug \
  -derivedDataPath /tmp/bookmarker-native-tests test -quiet
