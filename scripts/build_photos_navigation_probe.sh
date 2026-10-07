#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p artifacts/photos-navigation-probe
ruby scripts/generate_photos_navigation_probe.rb
swiftc -parse-as-library native/PhotosNavigationProbe/URLCandidates.swift \
  native/PhotosNavigationProbe/URLTests.swift -o build/photos-navigation-probe/url-tests
build/photos-navigation-probe/url-tests | tee artifacts/photos-navigation-probe/url-tests.log
xcodebuild -project build/photos-navigation-probe/PhotosNavigationProbe.xcodeproj \
  -scheme PhotosNavigationProbe -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build/photos-navigation-probe/DerivedData \
  CODE_SIGNING_ALLOWED=NO > artifacts/photos-navigation-probe/build.log 2>&1 || {
    tail -n 100 artifacts/photos-navigation-probe/build.log
    exit 1
  }
tail -n 10 artifacts/photos-navigation-probe/build.log
APP="$ROOT/build/photos-navigation-probe/DerivedData/Build/Products/Release-iphoneos/PhotosNavigationProbe.app"
PACKAGE="$ROOT/build/photos-navigation-probe/package"
mkdir -p "$PACKAGE/Payload"
ditto "$APP" "$PACKAGE/Payload/PhotosNavigationProbe.app"
cd "$PACKAGE"
zip -qry "$ROOT/artifacts/photos-navigation-probe/photos-navigation-probe-unsigned.ipa" Payload
cd "$ROOT"
python3 - <<'PY'
import hashlib, json, pathlib, plistlib, zipfile
path = pathlib.Path('artifacts/photos-navigation-probe/photos-navigation-probe-unsigned.ipa')
with zipfile.ZipFile(path) as archive:
    root = 'Payload/PhotosNavigationProbe.app/'
    info = plistlib.loads(archive.read(root + 'Info.plist'))
    share = plistlib.loads(archive.read(root + 'PlugIns/PhotosNavigationShare.appex/Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.kevin3627713.photosnavigationprobe'
    assert share['CFBundleIdentifier'] == info['CFBundleIdentifier'] + '.share'
    assert info['CFBundleShortVersionString'] == share['CFBundleShortVersionString'] == '0.1.1'
    assert info['CFBundleVersion'] == share['CFBundleVersion'] == '2'
    assert not any('SessionWidgets' in name or name.endswith('.mobileprovision') for name in archive.namelist())
    assert archive.read(root + info['CFBundleExecutable'])[:4] == b'\xcf\xfa\xed\xfe'
    assert archive.read(root + 'PlugIns/PhotosNavigationShare.appex/' + share['CFBundleExecutable'])[:4] == b'\xcf\xfa\xed\xfe'
    report = {'bundle': info['CFBundleIdentifier'], 'shareBundle': share['CFBundleIdentifier'],
              'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
              'size': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
path.with_name('package.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
PY
