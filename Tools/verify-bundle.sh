#!/bin/bash
#
# Sanity-checks a built MitthuAI.app (and optionally its .dmg) before it is
# shipped: both architectures present, Info.plist valid, signature intact, and
# the app inside the disk image is the one we just built.
#
#   ./Tools/verify-bundle.sh build/MitthuAI.app [build/MitthuAI.dmg]
#
set -euo pipefail

APP="${1:-build/MitthuAI.app}"
DMG="${2:-}"
NAME="MitthuAI"
BINARY="${APP}/Contents/MacOS/${NAME}"

fail() { echo "  ✗ $*" >&2; exit 1; }
ok()   { echo "  ✓ $*"; }

echo "Verifying ${APP}"

[ -d "$APP" ] || fail "no app bundle at ${APP}"
[ -x "$BINARY" ] || fail "missing executable ${BINARY}"
ok "executable present ($(du -h "$BINARY" | awk '{print $1}'))"

ARCHS="$(lipo -archs "$BINARY")"
for arch in arm64 x86_64; do
    case " $ARCHS " in
        *" $arch "*) ;;
        *) fail "binary is missing the ${arch} slice (has: ${ARCHS}) — build with --universal" ;;
    esac
done
ok "universal binary (${ARCHS})"

plutil -lint "${APP}/Contents/Info.plist" >/dev/null || fail "Info.plist is not valid"
# `defaults read` needs an absolute path with no .plist extension.
ABS_PLIST="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")/Contents/Info"
VERSION="$(defaults read "$ABS_PLIST" CFBundleShortVersionString)"
BUILD_NUM="$(defaults read "$ABS_PLIST" CFBundleVersion)"
ok "Info.plist valid (version ${VERSION}, build ${BUILD_NUM})"

[ -f "${APP}/Contents/Resources/AppIcon.icns" ] || fail "no app icon in the bundle"
ok "app icon bundled"

codesign --verify --deep --strict "$APP" || fail "code signature does not verify"
ok "signature verifies ($(codesign -dv "$APP" 2>&1 | awk -F= '/^Signature/{print $2}'))"

if [ -n "$DMG" ]; then
    echo "Verifying ${DMG}"
    [ -f "$DMG" ] || fail "no disk image at ${DMG}"
    hdiutil verify "$DMG" >/dev/null || fail "disk image is corrupt"
    MOUNT="$(mktemp -d)"
    hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
    trap 'hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; rm -rf "$MOUNT"' EXIT
    [ -d "${MOUNT}/${NAME}.app" ] || fail "${NAME}.app is not inside the disk image"
    [ -L "${MOUNT}/Applications" ] || fail "no /Applications drop target in the disk image"
    DMG_VERSION="$(defaults read "${MOUNT}/${NAME}.app/Contents/Info" CFBundleShortVersionString)"
    [ "$DMG_VERSION" = "$VERSION" ] \
        || fail "disk image holds version ${DMG_VERSION}, expected ${VERSION}"
    ok "disk image contains ${NAME}.app ${DMG_VERSION} + Applications link"
fi

echo "All checks passed."
