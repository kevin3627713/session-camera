#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts
if [[ ! -f artifacts/widget-simulator-devices.json ]]; then
  xcrun simctl list devices available --json > artifacts/widget-simulator-devices.json
fi
simulator_id="$(python3 -c '
import json
with open("artifacts/widget-simulator-devices.json") as source:
    devices = json.load(source)["devices"]
for runtime in sorted(devices, reverse=True):
    if ".iOS-18-" in runtime:
        iphones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
        if iphones:
            print(iphones[0]["udid"])
            break
')"
if [[ -z "$simulator_id" ]]; then echo "iOS 18 simulator required for Photos integration" >&2; exit 1; fi
app="$PWD/build/widget-photo-integration/WidgetPhotoIntegration.app"
mkdir -p "$app"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
diagnostic_flags=()
if [[ "${WIDGET_PHOTO_DIAGNOSTICS:-0}" == "1" ]]; then
  diagnostic_flags=(-D WIDGET_PHOTO_DIAGNOSTICS)
fi
xcrun swiftc -swift-version 5 -D WIDGET_INTEGRATION_TEST "${diagnostic_flags[@]}" -sdk "$sdk" -target "$(uname -m)-apple-ios18.0-simulator" \
  -o "$app/WidgetPhotoIntegration" native/WidgetHookTests/PhotoIntegrationApp.swift \
  ios/SessionWidgets/WidgetOptions.swift ios/SessionWidgets/PhotoLibrarySource.swift \
  ios/SessionWidgets/SessionWidgets.swift \
  native/WidgetDiagnostics/PhotoWidgetDiagnostics.swift \
  native/SessionCore/Sources/WidgetCore/PhotoSchedule.swift \
  > artifacts/widget-photo-compile.log 2>&1 || { cat artifacts/widget-photo-compile.log; exit 1; }
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.kevin3627713.sessioncamera.widgetphototests</string>
<key>CFBundleExecutable</key><string>WidgetPhotoIntegration</string>
<key>CFBundleName</key><string>Widget Photo Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>18.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
<key>NSPhotoLibraryUsageDescription</key><string>Simulator integration test with synthetic photos only.</string>
<key>NSPhotoLibraryAddUsageDescription</key><string>Create synthetic simulator fixtures.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$app"
xcrun simctl privacy "$simulator_id" grant photos-add com.kevin3627713.sessioncamera.widgetphototests
xcrun simctl privacy "$simulator_id" grant photos com.kevin3627713.sessioncamera.widgetphototests
# The iOS 18 simulator's simctl writes Photos auth_version=1. Its new Photos
# permission flow interprets that legacy record as needing an upgrade prompt,
# even though auth_value=2. Set version 2 ONLY for this synthetic test host,
# with the simulator shut down so tccd cannot cache/overwrite the change.
# Actual authorization is still checked through the production PhotoKit API.
tcc_database="$HOME/Library/Developer/CoreSimulator/Devices/$simulator_id/data/Library/TCC/TCC.db"
if [[ ! -f "$tcc_database" ]]; then echo "Missing simulator TCC database" >&2; exit 1; fi
xcrun simctl shutdown "$simulator_id"
sqlite3 "$tcc_database" "UPDATE access SET auth_version=2 WHERE service='kTCCServicePhotos' AND client='com.kevin3627713.sessioncamera.widgetphototests' AND auth_value=2;
SELECT service,client,auth_value,auth_version FROM access WHERE client='com.kevin3627713.sessioncamera.widgetphototests';" \
  | tee artifacts/widget-photo-simulator-authorization.txt
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl launch "$simulator_id" com.kevin3627713.sessioncamera.widgetphototests
container="$(xcrun simctl get_app_container "$simulator_id" com.kevin3627713.sessioncamera.widgetphototests data)"
report="$container/Documents/widget-photo-integration.json"
for attempt in $(seq 1 90); do
  if [[ -f "$report" ]]; then
    cp "$report" artifacts/widget-photo-integration.json
    python3 -c 'import json; r=json.load(open("artifacts/widget-photo-integration.json")); print(json.dumps(r,indent=2)); assert r["success"],r'
    exit 0
  fi
  sleep 1
done
echo "Photos integration report not produced within 90 seconds" >&2
xcrun simctl io "$simulator_id" screenshot artifacts/widget-photo-timeout.png || true
xcrun simctl spawn "$simulator_id" log show --last 2m --style compact \
  --predicate 'process == "WidgetPhotoIntegration" OR process == "tccd"' \
  > artifacts/widget-photo-runtime.log || true
exit 1
