#!/bin/bash
# App Store screenshots for each iPhone size App Store Connect asks for, via the FitMeScreenshots UI test
# (screenshot mode: demo closet, a packed sample trip, steady weather). Run from `make screenshots`.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# Simulator : folder. 6.3-inch (1206 x 2622) is the set App Store Connect requires; 6.9-inch (1320 x 2868) is optional.
sets=("iPhone 18 Pro:6.3-inch" "iPhone 18 Pro Max:6.9-inch")

for set in "${sets[@]}"; do
    device=${set%%:*}
    out="$root/docs/store/screenshots/${set##*:}"
    rm -rf "$out" && mkdir -p "$out"
    xcrun simctl boot "$device" 2>/dev/null || true
    xcrun simctl bootstatus "$device" -b >/dev/null
    xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 \
        --wifiBars 3 --cellularBars 4
    TEST_RUNNER_SCREENSHOT_DIR="$out" xcodebuild -project "$root/FitMe.xcodeproj" -derivedDataPath "$root/DerivedData" \
        -scheme FitMeScreenshots -destination "platform=iOS Simulator,name=$device" test | xcbeautify
done
