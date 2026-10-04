#!/usr/bin/env bash
set -euo pipefail

APP_PATH="build/ios/iphoneos/Runner.app"
IPA_NAME="ipa_ci_demo_manual_no_sign.ipa"

if [ ! -d "$APP_PATH" ]; then
  echo "Missing $APP_PATH. Run: flutter build ios --release --no-codesign" >&2
  exit 1
fi

rm -rf Payload
mkdir -p Payload
cp -R "$APP_PATH" Payload/Runner.app

if [ -d Payload/Runner.app/Frameworks ]; then
  find Payload/Runner.app/Frameworks -type d -name "*.framework" -exec codesign --force --sign - --preserve-metadata=identifier,entitlements {} \;
fi

zip -q -r "$IPA_NAME" Payload
echo "Created $IPA_NAME"
