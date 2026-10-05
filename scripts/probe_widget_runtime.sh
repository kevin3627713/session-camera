#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts
xcrun simctl list devices available --json > artifacts/widget-simulator-devices.json
simulator_id="$(python3 -c '
import json
with open("artifacts/widget-simulator-devices.json") as source:
    runtimes = json.load(source)["devices"]
for runtime in sorted(runtimes, reverse=True):
    if ".iOS-18-" in runtime:
        devices = [d for d in runtimes[runtime] if d["name"].startswith("iPhone")]
        if devices:
            print(devices[0]["udid"])
            break
')"
if [[ -z "$simulator_id" ]]; then
  echo "No installed iOS 18 simulator; runtime probe not performed." | tee artifacts/widget-runtime-probe.log
  exit 0
fi
sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun clang -fobjc-arc -fblocks -target "$(uname -m)-apple-ios18.0-simulator" \
  -isysroot "$sdk_path" -I ios/SessionWidgets \
  ios/SessionWidgets/WidgetBackgroundHook.m native/WidgetHookTests/RuntimeProbe.m \
  -framework Foundation -framework WidgetKit -framework SwiftUI \
  -o artifacts/widget-runtime-probe
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl spawn "$simulator_id" "$PWD/artifacts/widget-runtime-probe" 2>&1 | tee artifacts/widget-runtime-probe.log
