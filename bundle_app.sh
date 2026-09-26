#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "🔨 Building CultureMemoji in release mode..."
swift build -c release

APP_NAME="CultureMemoji.app"
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

echo "📦 Bundling into $APP_NAME..."
cp ".build/release/CultureMemoji" "$APP_NAME/Contents/MacOS/CultureMemoji"

# Info.plist
cat << 'EOF' > "$APP_NAME/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CultureMemoji</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.culture.CultureMemoji</string>
    <key>CFBundleName</key>
    <string>Memoji Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Memoji Studio uses your camera to mirror your facial expressions onto 3D Memojis in real time.</string>
</dict>
</plist>
EOF

if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_NAME/Contents/Resources/AppIcon.icns"
fi

echo "🔏 Signing app bundle with camera entitlements..."
codesign -s - --deep --force --entitlements entitlements.plist "$APP_NAME"

echo "✅ App bundle created successfully: $APP_NAME"
echo "👉 You can run it now with: open $APP_NAME"
