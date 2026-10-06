#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts
xcrun clang -fobjc-arc -framework Foundation -c ios/Shared/PhotoBridgeProtocol.m \
  -o artifacts/photo-bridge-protocol.o
xcrun swiftc -swift-version 5 -D PHOTO_BRIDGE_PROTOCOL_TEST \
  -import-objc-header ios/Shared/PhotoBridgeProtocol.h \
  ios/SessionPhotoBridge/PhotosBridgeRequest.swift native/WidgetPhotoBridgeTests/PayloadTests.swift \
  artifacts/photo-bridge-protocol.o -o artifacts/photo-bridge-payload-tests
artifacts/photo-bridge-payload-tests
