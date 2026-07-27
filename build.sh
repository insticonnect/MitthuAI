#!/bin/bash
set -e

APP_NAME="MitthuAI"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

# ./build.sh          → build build/MitthuAI.app
# ./build.sh --dmg    → also package build/MitthuAI.dmg (needs `dmgbuild`)
MAKE_DMG=0
for arg in "$@"; do
    case "$arg" in
        --dmg) MAKE_DMG=1 ;;
        -h|--help)
            echo "usage: ./build.sh [--dmg]"
            exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

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

echo "Compiling Swift sources ($(ls Sources/MitthuAI/*.swift | wc -l | tr -d " ") files)..."
swiftc \
    -O \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    ${PLUGIN_FLAGS} \
    Sources/MitthuAI/*.swift \
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

if [ "$MAKE_DMG" = "1" ]; then
    echo "Packaging disk image..."
    if command -v dmgbuild >/dev/null 2>&1; then
        rm -f "$DMG_PATH"
        dmgbuild -s dmgbuild-settings.py \
                 -D app="$APP_DIR" "$APP_NAME" "$DMG_PATH"
        echo "  ✓ ${DMG_PATH}"
    else
        echo "  ! dmgbuild not found — install it with: pip3 install dmgbuild" >&2
        exit 1
    fi
fi

echo "============================================="
echo "Done: ${APP_DIR}"
echo "Run:  open ${APP_DIR}"
echo "============================================="
