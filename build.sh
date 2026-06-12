#!/bin/bash
set -e

# Configuration
APP_NAME="Mitthu"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

echo "============================================="
echo "Building Mitthu for macOS"
echo "============================================="

# 1. Clean old builds
echo "Cleaning old build files..."
rm -rf "$BUILD_DIR"
mkdir -p "${APP_DIR}/Contents/"{MacOS,Resources}

# 2. Compile Swift source code
echo "Compiling Swift files..."
swiftc \
    -O \
    -sdk "$(xcrun --show-sdk-path)" \
    -target "arm64-apple-macosx11.0" \
    Sources/Mitthu/main.swift \
    Sources/Mitthu/AppDelegate.swift \
    Sources/Mitthu/Models.swift \
    Sources/Mitthu/Database.swift \
    Sources/Mitthu/Tracker.swift \
    Sources/Mitthu/DashboardView.swift \
    Sources/Mitthu/HttpServer.swift \
    -o "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# 3. Copy Bundle Metadata and Resources
echo "Configuring App Bundle Info.plist..."
cp Info.plist "${APP_DIR}/Contents/Info.plist"

# Setup basic placeholder app icon if custom icon is missing
echo "Creating icon files..."
# Create a temporary icon image
mkdir -p "${BUILD_DIR}/Icon.iconset"
# Create a dummy image or copy system default
cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/UserIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns" || true

# 4. Verification
echo "App bundle successfully created at ${APP_DIR}!"

# 5. Packaging DMG Disk Image
echo "---------------------------------------------"
echo "Building Styled DMG Installer..."
echo "---------------------------------------------"

# Check if dmgbuild is installed, otherwise build a simple DMG using hdiutil
if command -v dmgbuild &> /dev/null; then
    echo "Using dmgbuild to generate styled installer..."
    dmgbuild -s dmgbuild-settings.py "Mitthu Installer" "${BUILD_DIR}/${APP_NAME}.dmg"
else
    echo "dmgbuild not found. Generating a basic DMG using hdiutil..."
    # Create temp directory for simple layout
    TMP_DMG_DIR="${BUILD_DIR}/dmg_layout"
    mkdir -p "$TMP_DMG_DIR"
    cp -r "$APP_DIR" "$TMP_DMG_DIR/"
    ln -s /Applications "$TMP_DMG_DIR/Applications"
    
    # Run hdiutil
    rm -f "${BUILD_DIR}/${APP_NAME}.dmg"
    hdiutil create -volname "Mitthu" -srcfolder "$TMP_DMG_DIR" -ov -format UDZO "${BUILD_DIR}/${APP_NAME}.dmg"
    rm -rf "$TMP_DMG_DIR"
fi

echo "============================================="
echo "Success! DMG built at ${BUILD_DIR}/${APP_NAME}.dmg"
echo "============================================="
