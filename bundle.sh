#!/bin/bash
set -euo pipefail

APP_NAME="H0Ver"
EXECUTABLE="mac-gesture-lock"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building release..."
swift build -c release 2>&1

BUILT_EXECUTABLE=".build/release/${EXECUTABLE}"
if [ ! -f "$BUILT_EXECUTABLE" ]; then
    echo "Error: executable not found at $BUILT_EXECUTABLE"
    exit 1
fi

echo "Creating app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
cp "${BUILT_EXECUTABLE}" "${MACOS_DIR}/${EXECUTABLE}"

# Copy .env if it exists
if [ -f ".env" ]; then
    cp ".env" "${MACOS_DIR}/.env"
fi

# Copy icon if it exists
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.h0ver.lockscreen</string>
    <key>CFBundleVersion</key>
    <string>1.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSAppleEventsUsageDescription</key>
    <string>H0Ver needs access to display the currently playing track.</string>
    <key>NSLocationUsageDescription</key>
    <string>H0Ver needs your location to display accurate local weather on the lock screen.</string>
</dict>
</plist>
EOF

echo ""
echo "Done! Created ${BUNDLE_DIR}"
echo ""
echo "To run:  open ${BUNDLE_DIR}"
echo "To install:  cp -r ${BUNDLE_DIR} /Applications/"
