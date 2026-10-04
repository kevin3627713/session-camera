#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts/ui
app="$PWD/build/ui-preview/CameraUIPreview.app"
mkdir -p "$app"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
architecture="$(uname -m)"

# Compile the actual camera/gallery/editor sources into a tiny simulator host,
# without Flutter or an XCTest host. The demo flag is absent from Runner.
xcrun swiftc -swift-version 5 -O -DCAMERA_UI_PREVIEW -sdk "$sdk" \
  -target "$architecture-apple-ios17.0-simulator" -o "$app/CameraUIPreview" \
  native/UIPreview/PreviewApp.swift \
  ios/Runner/CameraScreen.swift ios/Runner/CameraEngine.swift \
  ios/Runner/SessionStore.swift ios/Runner/PhotoEditor.swift \
  native/SessionCore/Sources/SessionCore/SessionLedger.swift \
  native/SessionCore/Sources/PhotoCore/PhotoRendering.swift \
  > artifacts/ui/compile.log 2>&1 || { cat artifacts/ui/compile.log; exit 1; }

cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.kevin3627713.sessioncamera.uipreview</string>
<key>CFBundleExecutable</key><string>CameraUIPreview</string>
<key>CFBundleName</key><string>Camera UI Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIStatusBarHidden</key><true/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$app"

xcrun simctl list devices available --json > artifacts/ui/devices.json
python3 - <<'PY' > artifacts/ui/selected-devices.tsv
import json, subprocess
data = json.load(open("artifacts/ui/devices.json"))["devices"]
runtimes = sorted((key for key in data if ".iOS-" in key), reverse=True)
runtime = next((key for key in runtimes if ".iOS-18-" in key), runtimes[0])
devices = [device for device in data[runtime] if device["name"].startswith("iPhone")]
regular = next((d for d in devices if d["name"] == "iPhone 13"), None)
if regular is None:
    device_types = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "--json"]))["devicetypes"]
    reference_type = next((d for d in device_types if d["identifier"].endswith(".iPhone-13")), None)
    if reference_type:
        identifier = subprocess.check_output(["xcrun", "simctl", "create", "iPhone 13 Reference",
                                             reference_type["identifier"], runtime], text=True).strip()
        regular = {"udid": identifier, "name": "iPhone 13 (390x844 reference geometry)"}
    else:
        regular = next((d for d in devices if d["name"] == "iPhone 16 Pro"), devices[0])
compact = next((d for d in devices if "SE" in d["name"]), None)
print("regular", regular["udid"], regular["name"], runtime, sep="\t")
if compact:
    print("compact", compact["udid"], compact["name"], runtime, sep="\t")
PY

while IFS=$'\t' read -r layout simulator_id device_name runtime; do
  echo "Preview on $device_name ($runtime)"
  xcrun simctl boot "$simulator_id" || true
  xcrun simctl bootstatus "$simulator_id" -b
  xcrun simctl status_bar "$simulator_id" override --time 9:41 --batteryState charged --batteryLevel 100
  xcrun simctl ui "$simulator_id" appearance dark
  xcrun simctl install "$simulator_id" "$app"
  data_directory="$(xcrun simctl get_app_container "$simulator_id" com.kevin3627713.sessioncamera.uipreview data)"
  for screen in camera controls video gallery editor crop grid; do
    marker="$data_directory/Documents/ui-preview-ready-$screen"
    rm -f "$marker"
    xcrun simctl terminate "$simulator_id" com.kevin3627713.sessioncamera.uipreview 2>/dev/null || true
    xcrun simctl launch "$simulator_id" com.kevin3627713.sessioncamera.uipreview \
      -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN --screen "$screen"
    for attempt in $(seq 1 90); do
      if [ -f "$marker" ]; then break; fi
      sleep 1
    done
    if [ ! -f "$marker" ]; then
      echo "Requested $layout/$screen did not finish rendering within 90 seconds." >&2
      exit 1
    fi
    xcrun simctl io "$simulator_id" screenshot "artifacts/ui/$layout-$screen.png"
  done
  xcrun simctl shutdown "$simulator_id"
done < artifacts/ui/selected-devices.tsv

python3 - <<'PY'
import hashlib
from pathlib import Path
screens = ["camera", "controls", "video", "gallery", "editor", "crop", "grid"]
for row in Path("artifacts/ui/selected-devices.tsv").read_text().splitlines():
    layout = row.split("\t")[0]
    hashes = [hashlib.sha256(Path(f"artifacts/ui/{layout}-{screen}.png").read_bytes()).hexdigest()
              for screen in screens]
    assert len(set(hashes)) == len(screens), f"Duplicate screenshots for {layout}: a requested screen was not captured"
print("All requested screenshots are present and distinct.")
PY
