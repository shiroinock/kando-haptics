#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/kando-haptics-release.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
mkdir -p "$staging_dir/Sources" "$repo_dir/dist"
cp "$repo_dir/Sources/main.swift" "$staging_dir/Sources/main.swift"
cp "$repo_dir/build.sh" "$repo_dir/LICENSE" "$staging_dir/"
bash "$staging_dir/build.sh"
app_path="$staging_dir/Kando Haptics.app"
codesign --verify --deep --strict "$app_path"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
archive="Kando-Haptics-${version}-macOS-$(uname -m).zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$repo_dir/dist/$archive"
(cd "$repo_dir/dist" && shasum -a 256 "$archive" > SHA256SUMS.txt)
printf 'Created %s\n' "$repo_dir/dist/$archive"
