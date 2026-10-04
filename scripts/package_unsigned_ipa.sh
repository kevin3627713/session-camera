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
ipa_path="$PWD/$ipa_name"
if [[ -e "$ipa_path" ]]; then rm "$ipa_path"; fi
(cd "$package_dir" && zip -q -r "$ipa_path" Payload)
unzip -tq "$ipa_path"
python3 scripts/verify_ipa.py "$ipa_path"
echo "Created $ipa_path"
