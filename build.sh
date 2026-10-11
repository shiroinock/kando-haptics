#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/kando-haptics-build.XXXXXX")
trap 'rm -rf "$cache_dir"' EXIT
app_dir="Kando Haptics.app/Contents"
mkdir -p "$app_dir/MacOS"
swiftc -swift-version 5 -O -target "$(uname -m)-apple-macos13.0" -module-cache-path "$cache_dir" \
  -framework AppKit Sources/main.swift -o "$app_dir/MacOS/KandoHaptics"
cat > "$app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KandoHaptics</string>
<key>CFBundleIdentifier</key><string>dev.shiroino.kando-haptics</string>
<key>CFBundleName</key><string>Kando Haptics</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "Kando Haptics.app"
"$app_dir/MacOS/KandoHaptics" --self-test
