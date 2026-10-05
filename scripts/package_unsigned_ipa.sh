#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-build/ios/iphoneos/Runner.app}"
ipa_name="${2:-session-camera-unsigned.ipa}"
if [[ ! -d "$app_path" ]]; then
  echo "Missing app: $app_path. Run flutter build ios --release --no-codesign." >&2
  exit 1
fi

# Work only in a fresh temporary directory; never remove a caller's Payload.
package_dir="$(mktemp -d)"
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Payload"
ditto "$app_path" "$package_dir/Payload/Runner.app"
if [[ -d "$package_dir/Payload/Runner.app/Frameworks" ]]; then
  while IFS= read -r -d '' framework; do
    codesign --force --sign - --preserve-metadata=identifier,entitlements "$framework"
  done < <(find "$package_dir/Payload/Runner.app/Frameworks" -type d -name '*.framework' -print0)
fi
extension_path="$package_dir/Payload/Runner.app/PlugIns/SessionWidgets.appex"
if [[ ! -d "$extension_path" ]]; then
  echo "Missing embedded SessionWidgets.appex; refusing to package a widget-less build." >&2
  exit 1
fi
if [[ -d "$extension_path/Frameworks" ]]; then
  while IFS= read -r -d '' framework; do
    codesign --force --sign - --preserve-metadata=identifier,entitlements "$framework"
  done < <(find "$extension_path/Frameworks" -type d -name '*.framework' -print0)
fi
# Ad-hoc signatures are placeholders for the user's re-signing tool, not an
# Apple development certificate. Sign nested code before packaging the app.
codesign --force --sign - --preserve-metadata=identifier,entitlements "$extension_path"
ipa_path="$PWD/$ipa_name"
if [[ -e "$ipa_path" ]]; then rm "$ipa_path"; fi
(cd "$package_dir" && zip -q -r "$ipa_path" Payload)
unzip -tq "$ipa_path"
verification_flags=()
if [[ "${WIDGET_PHOTO_DIAGNOSTICS:-0}" == "1" ]]; then
  verification_flags=(--widget-diagnostics)
fi
python3 scripts/verify_ipa.py "$ipa_path" "${verification_flags[@]}"
echo "Created $ipa_path"
