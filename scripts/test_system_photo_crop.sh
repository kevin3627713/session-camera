#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts
xcrun clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
  -I ios/SessionWidgets -framework Foundation -framework CoreGraphics \
  ios/SessionWidgets/SystemPhotoCrop.m native/WidgetHookTests/SystemPhotoCropTests.m \
  -o artifacts/system-photo-crop-tests
artifacts/system-photo-crop-tests 2>&1 | tee artifacts/system-photo-crop-tests.log
