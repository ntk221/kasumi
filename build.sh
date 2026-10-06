#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="Kasumi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O Kasumi.swift -o "$APP/Contents/MacOS/Kasumi"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Kasumi</string>
    <key>CFBundleIdentifier</key><string>local.kasumi</string>
    <key>CFBundleName</key><string>Kasumi</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "できました → open $APP"
