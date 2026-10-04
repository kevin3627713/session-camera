#!/usr/bin/env bash
set -euo pipefail

simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if ".iOS-" in runtime:
        iphones = [device for device in devices[runtime] if device["name"].startswith("iPhone")]
        if iphones:
            print(iphones[0]["udid"])
            break
else:
    raise SystemExit("No iPhone simulator runtime installed")
')"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
flutter build ios --simulator --debug --config-only --no-pub
mkdir -p artifacts
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO \
  -resultBundlePath artifacts/PhotoRenderer.xcresult \
  CODE_SIGNING_ALLOWED=NO > artifacts/native-tests.log 2>&1 || {
    tail -n 100 artifacts/native-tests.log
    exit 1
  }
tail -n 24 artifacts/native-tests.log

# Real UI screenshot from a simulator (no camera hardware). These artifacts do
# not claim real camera, permissions, signing or Guided Access were tested.
xcrun simctl install "$simulator_id" build/ios/iphonesimulator/Runner.app
xcrun simctl privacy "$simulator_id" grant photos com.kevin3627713.sessioncamera
xcrun simctl launch "$simulator_id" com.kevin3627713.sessioncamera
sleep 5
xcrun simctl io "$simulator_id" screenshot artifacts/simulator.png
