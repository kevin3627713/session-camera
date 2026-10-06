#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts/widget-url-probe
if ! ruby -e "require 'xcodeproj'"; then gem install xcodeproj --no-document; fi
ruby scripts/generate_widget_url_probe.rb
python3 - <<'PY'
import pathlib, plistlib
directory = pathlib.Path('build/widget-url-probe')
for name, suffix, extra in [
    ('URLProbe', '', {'CFBundleDisplayName': 'URL Probe', 'UILaunchScreen': {},
                     'NSPhotoLibraryUsageDescription': 'Synthetic simulator photo only.',
                     'NSPhotoLibraryAddUsageDescription': 'Create a synthetic simulator photo.'}),
    ('URLProbeWidget', '.widget', {'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'},
                                  'NSPhotoLibraryUsageDescription': 'Synthetic simulator photo only.'}),
    ('URLProbeShare', '.share', {'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.share-services',
        'NSExtensionPrincipalClass': 'ProbeShareController', 'NSExtensionContextClass': 'NSExtensionContext',
        'NSExtensionContextHostClass': 'NSExtensionContext',
        'NSExtensionAttributes': {'NSExtensionActivationRule': 'TRUEPREDICATE'}}}),
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
xcodebuild build-for-testing -project build/widget-url-probe/URLProbe.xcodeproj -scheme URLProbe \
    -derivedDataPath build/widget-url-probe/DerivedData \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    CODE_SIGNING_ALLOWED=NO > artifacts/widget-url-probe/build.log 2>&1 || {
        tail -n 80 artifacts/widget-url-probe/build.log; exit 1;
    }
app="$PWD/build/widget-url-probe/DerivedData/Build/Products/Debug-iphonesimulator/URLProbe.app"
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
xcodebuild test-without-building -project build/widget-url-probe/URLProbe.xcodeproj -scheme URLProbe \
    -derivedDataPath build/widget-url-probe/DerivedData \
    -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO \
    -resultBundlePath artifacts/widget-url-probe/URLProbe.xcresult \
    CODE_SIGNING_ALLOWED=NO > artifacts/widget-url-probe/ui-tests.log 2>&1
test_status=$?
xcrun simctl io "$simulator_id" screenshot artifacts/widget-url-probe/final-screen.png
xcrun simctl spawn "$simulator_id" log show --last 5m --style compact \
    --predicate 'eventMessage CONTAINS "SCURLPROBE"' > artifacts/widget-url-probe/dispatch.log
xcrun simctl spawn "$simulator_id" log show --last 3m --style compact \
    --predicate 'eventMessage CONTAINS "openURL" OR eventMessage CONTAINS "open url" OR eventMessage CONTAINS "not allowed"' \
    > artifacts/widget-url-probe/system-url.log
set -e
tail -n 80 artifacts/widget-url-probe/ui-tests.log
python3 - <<'PY'
from pathlib import Path
for line in Path('artifacts/widget-url-probe/ui-tests.log').read_text().splitlines():
    if 'error:' in line or 'SCURLPROBE UI route=' in line: print(line.split('Attributes:')[0])
PY
cat artifacts/widget-url-probe/dispatch.log
xcrun xcresulttool export attachments --path artifacts/widget-url-probe/URLProbe.xcresult \
    --output-path artifacts/widget-url-probe/screenshots || true
python3 - <<'PY'
import json, pathlib, re, os
directory=pathlib.Path('artifacts/widget-url-probe')
ui=(directory/'ui-tests.log').read_text()
rows=[]
for route,photos,host,state in re.findall(r'SCURLPROBE UI route=(.*?) photosForeground=(true|false) hostForeground=(true|false) hostState=(\d+)',ui):
    rows.append({'route':route,'photosForeground':photos=='true','hostForeground':host=='true','hostState':int(state)})
report={'sourceCommit':os.environ.get('GITHUB_SHA'),'context':'Actual iOS 18 simulator home-screen widget; containing app terminated before taps',
        'observedRoutes':rows, 'allRoutesObserved':len(rows)==4,
        'note':'Foreground observations must be combined with dispatch.log. Method acceptance is not proof of the selected Photos asset.'}
(directory/'observations.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
PY
exit "$test_status"
