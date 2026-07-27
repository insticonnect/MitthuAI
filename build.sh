#!/bin/bash
set -e

APP_NAME="MitthuAI"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

# Build for the machine we're on (arm64 on Apple Silicon, x86_64 on Intel).
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx12.0"

echo "============================================="
echo "Building ${APP_NAME} for macOS (${TARGET})"
echo "============================================="

echo "Cleaning old build..."
rm -rf "$BUILD_DIR"
mkdir -p "${APP_DIR}/Contents/"{MacOS,Resources}

# Newer SDKs implement SwiftUI property wrappers (@State etc.) as compiler
# macros; bare swiftc needs to be told where the macro plugins live.
SDK_PATH="$(xcrun --show-sdk-path)"
TOOLCHAIN_USR="$(dirname "$(dirname "$(xcrun --find swiftc)")")"
PLUGIN_FLAGS=""
for p in "${SDK_PATH}/usr/lib/swift/host/plugins" \
         "${TOOLCHAIN_USR}/lib/swift/host/plugins"; do
    if [ -d "$p" ]; then
        PLUGIN_FLAGS="${PLUGIN_FLAGS} -plugin-path ${p}"
    fi
done

echo "Compiling Swift sources..."
swiftc \
    -O \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    ${PLUGIN_FLAGS} \
    Sources/MitthuAI/main.swift \
    Sources/MitthuAI/AppDelegate.swift \
    Sources/MitthuAI/Config.swift \
    Sources/MitthuAI/LoginItem.swift \
    Sources/MitthuAI/Keychain.swift \
    Sources/MitthuAI/AccountPairing.swift \
    Sources/MitthuAI/RelayClient.swift \
    Sources/MitthuAI/SQLiteDB.swift \
    Sources/MitthuAI/Store.swift \
    Sources/MitthuAI/Embeddings.swift \
    Sources/MitthuAI/AXReader.swift \
    Sources/MitthuAI/Tracker.swift \
    Sources/MitthuAI/ContentCapture.swift \
    Sources/MitthuAI/Extractors.swift \
    Sources/MitthuAI/DateParse.swift \
    Sources/MitthuAI/ModelAssist.swift \
    Sources/MitthuAI/ReminderScheduler.swift \
    Sources/MitthuAI/Digest.swift \
    Sources/MitthuAI/HttpServer.swift \
    Sources/MitthuAI/Api.swift \
    Sources/MitthuAI/CalendarExport.swift \
    Sources/MitthuAI/McpServer.swift \
    Sources/MitthuAI/DashboardHTML.swift \
    Sources/MitthuAI/MenuBarView.swift \
    -o "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo "Configuring app bundle..."
cp Info.plist "${APP_DIR}/Contents/Info.plist"

# Generate the parrot app icon from Tools/MakeIcon.swift (AppKit vectors →
# .iconset → .icns). Falls back to a stock icon if anything here fails so a
# toolchain hiccup can never break the build.
echo "Generating app icon..."
ICONSET="${BUILD_DIR}/AppIcon.iconset"
if swiftc -O -sdk "$SDK_PATH" -target "$TARGET" Tools/MakeIcon.swift \
       -o "${BUILD_DIR}/makeicon" 2>/dev/null \
   && "${BUILD_DIR}/makeicon" "$ICONSET" 2>/dev/null \
   && iconutil -c icns "$ICONSET" -o "${APP_DIR}/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    echo "  ✓ parrot icon generated"
    rm -rf "$ICONSET" "${BUILD_DIR}/makeicon"
else
    echo "  ! icon generation failed — using a stock icon"
    cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/UserIcon.icns \
       "${APP_DIR}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

echo "Signing (ad-hoc)..."
codesign --force --deep -s - --entitlements entitlements.plist "${APP_DIR}" || true

echo "============================================="
echo "Done: ${APP_DIR}"
echo "Run:  open ${APP_DIR}"
echo "============================================="
