#!/bin/bash
set -e

APP_NAME="MitthuAI"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

# ./build.sh                    → build/MitthuAI.app for this Mac
# ./build.sh --universal        → arm64 + x86_64 in one bundle (what we ship)
# ./build.sh --dmg              → also package build/MitthuAI.dmg (needs dmgbuild)
# ./build.sh --version 1.2.0    → stamp that version into the bundle
MAKE_DMG=0
UNIVERSAL=0
VERSION="${MITTHUAI_VERSION:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --dmg) MAKE_DMG=1 ;;
        --universal) UNIVERSAL=1 ;;
        --version) VERSION="$2"; shift ;;
        --version=*) VERSION="${1#*=}" ;;
        -h|--help)
            echo "usage: ./build.sh [--universal] [--dmg] [--version X.Y.Z]"
            exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Releases are built for both architectures; a local build targets this Mac only
# so it stays fast.
if [ "$UNIVERSAL" = "1" ]; then
    ARCHS=(arm64 x86_64)
else
    ARCHS=("$(uname -m)")
fi
HOST_TARGET="$(uname -m)-apple-macosx12.0"

echo "============================================="
echo "Building ${APP_NAME} for macOS (${ARCHS[*]})"
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

# Every file in Sources/MitthuAI is compiled — adding a source file needs no
# change here.
SOURCES=(Sources/MitthuAI/*.swift)
echo "Compiling ${#SOURCES[@]} Swift sources..."

SLICES=()
for arch in "${ARCHS[@]}"; do
    echo "  → ${arch}"
    swiftc \
        -O \
        -sdk "$SDK_PATH" \
        -target "${arch}-apple-macosx12.0" \
        ${PLUGIN_FLAGS} \
        "${SOURCES[@]}" \
        -o "${BUILD_DIR}/${APP_NAME}-${arch}"
    SLICES+=("${BUILD_DIR}/${APP_NAME}-${arch}")
done

BINARY="${APP_DIR}/Contents/MacOS/${APP_NAME}"
if [ "${#SLICES[@]}" -gt 1 ]; then
    echo "Merging architectures..."
    lipo -create "${SLICES[@]}" -output "$BINARY"
else
    mv "${SLICES[0]}" "$BINARY"
fi
rm -f "${SLICES[@]}"
lipo -info "$BINARY" | sed 's/^/  /'

echo "Configuring app bundle..."
cp Info.plist "${APP_DIR}/Contents/Info.plist"

# A release stamps its tag into the bundle so About/Finder and crash reports
# agree with the version on the website.
if [ -n "$VERSION" ]; then
    SHORT_VERSION="${VERSION#v}"
    BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleShortVersionString ${SHORT_VERSION}" \
        -c "Set :CFBundleVersion ${BUILD_NUMBER}" \
        "${APP_DIR}/Contents/Info.plist"
    echo "  version ${SHORT_VERSION} (build ${BUILD_NUMBER})"
fi

# Generate the parrot app icon from Tools/MakeIcon.swift (AppKit vectors →
# .iconset → .icns). Falls back to a stock icon if anything here fails so a
# toolchain hiccup can never break the build.
echo "Generating app icon..."
ICONSET="${BUILD_DIR}/AppIcon.iconset"
if swiftc -O -sdk "$SDK_PATH" -target "$HOST_TARGET" Tools/MakeIcon.swift \
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

# Ad-hoc signature. Enough for a Mac to run the app once the installer strips
# the quarantine flag; see docs/RELEASING.md for Developer ID + notarization.
echo "Signing (ad-hoc)..."
codesign --force --deep -s - --entitlements entitlements.plist "${APP_DIR}" || true

if [ "$MAKE_DMG" = "1" ]; then
    echo "Packaging disk image..."
    if ! command -v dmgbuild >/dev/null 2>&1; then
        echo "  ! dmgbuild not found — install it with: pip3 install dmgbuild" >&2
        exit 1
    fi
    rm -f "$DMG_PATH"
    dmgbuild -s dmgbuild-settings.py \
             -D app="$APP_DIR" "$APP_NAME" "$DMG_PATH"
    echo "  ✓ ${DMG_PATH}"
fi

echo "============================================="
echo "Done: ${APP_DIR}"
echo "Run:  open ${APP_DIR}"
echo "============================================="
