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
    Sources/MitthuAI/BrandLogo.swift \
    Sources/MitthuAI/MenuBarView.swift \
    -o "${APP_DIR}/Contents/MacOS/${APP_NAME}"

echo "Configuring app bundle..."
cp Info.plist "${APP_DIR}/Contents/Info.plist"

# Brand assets. The logo PNGs are read at runtime (menu bar, popover and the
# dashboard's inline copy); the wordmark face is registered app-privately
# through Info.plist's ATSApplicationFontsPath.
echo "Copying brand assets..."
mkdir -p "${APP_DIR}/Contents/Resources/Brand" "${APP_DIR}/Contents/Resources/Fonts"
cp Resources/Brand/*.png "${APP_DIR}/Contents/Resources/Brand/"
cp Resources/Fonts/* "${APP_DIR}/Contents/Resources/Fonts/"

# The app icon is the logo, built from Resources/Brand/icon.icon and committed
# as an .icns — no generation step, so what ships is exactly the artwork.
cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"

echo "Signing (ad-hoc)..."
codesign --force --deep -s - --entitlements entitlements.plist "${APP_DIR}" || true

echo "============================================="
echo "Done: ${APP_DIR}"
echo "Run:  open ${APP_DIR}"
echo "============================================="
