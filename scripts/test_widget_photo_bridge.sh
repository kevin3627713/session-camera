#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts/widget-photo-bridge
if ! ruby -e "require 'xcodeproj'"; then gem install xcodeproj --no-document; fi
ruby scripts/generate_widget_photo_bridge_test.rb
python3 - <<'PY'
import pathlib, plistlib
directory = pathlib.Path('build/widget-photo-bridge')
for name, suffix, extra in [
    ('URLProbe', '', {'CFBundleDisplayName': 'URL Probe', 'UILaunchScreen': {},
                     'NSPhotoLibraryUsageDescription': 'Synthetic simulator photo only.',
                     'NSPhotoLibraryAddUsageDescription': 'Create a synthetic simulator photo.'}),
    ('URLProbeWidget', '.widget', {'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'},
                                  'NSPhotoLibraryUsageDescription': 'Synthetic simulator photo only.'}),
    ('SessionPhotoBridge', '.rewrittenphotosbridge', {
        'NSPhotoLibraryUsageDescription': 'Validate the clicked synthetic test photo.',
        'NSExtension': plistlib.loads(pathlib.Path('ios/SessionPhotoBridge/Info.plist').read_bytes())['NSExtension']}),
    ('URLProbeUITests', '.uitests', {})
]:
    info = {'CFBundleIdentifier': 'com.kevin3627713.sessioncamera.urlprobe' + suffix,
        'CFBundleExecutable': name, 'CFBundleName': name, 'CFBundleDisplayName': 'URL Probe', 'CFBundleVersion': '1',
        'CFBundleShortVersionString': '1.0', 'CFBundleInfoDictionaryVersion': '6.0',
        'CFBundlePackageType': 'APPL' if name == 'URLProbe' else 'BNDL' if name.endswith('Tests') else 'XPC!',
        'MinimumOSVersion': '18.0', 'UIDeviceFamily': [1],
        'LSApplicationQueriesSchemes': ['photos-navigation'], **extra}
    (directory / (name + '.plist')).write_bytes(plistlib.dumps(info))
PY
simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
for runtime,devices in sorted(json.load(sys.stdin)["devices"].items(),reverse=True):
    if ".iOS-18-" in runtime:
        phones=[d for d in devices if d["name"].startswith("iPhone")]
        if phones: print(phones[0]["udid"]); break
')"
if [[ -z "$simulator_id" ]]; then echo 'iOS 18 simulator required' >&2; exit 1; fi
xcodebuild build-for-testing -project build/widget-photo-bridge/URLProbe.xcodeproj -scheme URLProbe \
    -derivedDataPath build/widget-photo-bridge/DerivedData \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    CODE_SIGNING_ALLOWED=NO > artifacts/widget-photo-bridge/build.log 2>&1 || {
        tail -n 80 artifacts/widget-photo-bridge/build.log; exit 1;
    }
app="$PWD/build/widget-photo-bridge/DerivedData/Build/Products/Debug-iphonesimulator/URLProbe.app"
for extension in "$app"/PlugIns/*.appex; do codesign --force --sign - "$extension"; done
codesign --force --sign - "$app"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$app"
xcrun simctl privacy "$simulator_id" grant photos com.kevin3627713.sessioncamera.urlprobe
xcrun simctl privacy "$simulator_id" grant photos-add com.kevin3627713.sessioncamera.urlprobe
xcrun simctl shutdown "$simulator_id"
sqlite3 "$HOME/Library/Developer/CoreSimulator/Devices/$simulator_id/data/Library/TCC/TCC.db" \
    "UPDATE access SET auth_version=2 WHERE service='kTCCServicePhotos' AND client='com.kevin3627713.sessioncamera.urlprobe' AND auth_value=2;"
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
set +e
xcodebuild test-without-building -project build/widget-photo-bridge/URLProbe.xcodeproj -scheme URLProbe \
    -derivedDataPath build/widget-photo-bridge/DerivedData \
    -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO \
    -resultBundlePath artifacts/widget-photo-bridge/URLProbe.xcresult \
    CODE_SIGNING_ALLOWED=NO > artifacts/widget-photo-bridge/ui-tests.log 2>&1
test_status=$?
xcrun simctl io "$simulator_id" screenshot artifacts/widget-photo-bridge/final-screen.png
xcrun simctl spawn "$simulator_id" log show --last 5m --style compact \
    --predicate 'eventMessage CONTAINS "SCURLPROBE" OR eventMessage CONTAINS "SCBRIDGE"' > artifacts/widget-photo-bridge/dispatch.log
xcrun simctl spawn "$simulator_id" log show --last 3m --style compact \
    --predicate 'eventMessage CONTAINS "openURL" OR eventMessage CONTAINS "open url" OR eventMessage CONTAINS "not allowed"' \
    > artifacts/widget-photo-bridge/system-url.log
xcrun simctl spawn "$simulator_id" log show --last 6m --style compact \
    --predicate 'process == "URLProbeWidget" OR eventMessage CONTAINS "urlprobe.widget" OR eventMessage CONTAINS "URLProbeWidget"' \
    > artifacts/widget-photo-bridge/widget-runtime.log
set -e
tail -n 80 artifacts/widget-photo-bridge/ui-tests.log
python3 - <<'PY'
from pathlib import Path
for line in Path('artifacts/widget-photo-bridge/ui-tests.log').read_text().splitlines():
    if 'error:' in line or 'SCBRIDGE UI mode=' in line: print(line.split('Attributes:')[0])
PY
cat artifacts/widget-photo-bridge/dispatch.log
xcrun xcresulttool export attachments --path artifacts/widget-photo-bridge/URLProbe.xcresult \
    --output-path artifacts/widget-photo-bridge/screenshots || true
python3 - <<'PY'
import json, pathlib, re, os
directory=pathlib.Path('artifacts/widget-photo-bridge')
ui=(directory/'ui-tests.log').read_text()
rows=[]
for mode,photos,state in re.findall(r'SCBRIDGE UI mode=(cold|warm) photosForeground=(true|false) hostState=(\d+) targetTime=10:13PM',ui):
    rows.append({'mode':mode,'photosForeground':photos=='true','hostState':int(state),'targetTime':'10:13 PM'})
dispatch=(directory/'dispatch.log').read_text()
accepted=len(re.findall(r'SCBRIDGE client finished accepted=1 code=0',dispatch))
report={'sourceCommit':os.environ.get('GITHUB_SHA'),
        'context':'Actual iOS 18 home-screen widget using production bridge and independently rewritten Share identifier',
        'observedRoutes':rows,'acceptedRequests':accepted,
        'passed':len(rows)==2 and all(r['photosForeground'] and r['hostState']==1 for r in rows) and accepted>=2}
(directory/'observations.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
assert report['passed'], 'Production bridge, target asset or completion callback failed'
PY
exit "$test_status"
