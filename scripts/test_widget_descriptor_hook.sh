#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts
xcrun clang -fobjc-arc -fblocks -Wall -Wextra \
  -I ios/SessionWidgets ios/SessionWidgets/WidgetBackgroundHook.m \
  native/WidgetHookTests/DescriptorHookTests.m -framework Foundation \
  -o artifacts/widget-descriptor-tests
artifacts/widget-descriptor-tests 2>&1 | tee artifacts/widget-descriptor-tests.log
