#!/bin/bash
#
# MitthuAI installer — downloads the latest signed disk image from GitHub
# Releases and installs it into /Applications.
#
#   curl -fsSL https://mitthuai.com/install.sh | bash
#
# Environment overrides:
#   MITTHUAI_VERSION   release tag to install (default: latest), e.g. v1.2.0
#   MITTHUAI_DMG_URL   install this disk image instead (skips checksum check)
#
set -euo pipefail

APP_NAME="MitthuAI"
REPO="${MITTHUAI_REPO:-insticonnect/MitthuAI}"
VERSION="${MITTHUAI_VERSION:-latest}"

if [ "$VERSION" = "latest" ]; then
    RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"
else
    RELEASE_BASE="https://github.com/${REPO}/releases/download/${VERSION}"
fi
DMG_URL="${MITTHUAI_DMG_URL:-${RELEASE_BASE}/${APP_NAME}.dmg}"
SUMS_URL="${RELEASE_BASE}/SHA256SUMS.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

say()  { echo -e "${BLUE}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}" >&2; }
die()  { echo -e "${RED}Error: $*${NC}" >&2; exit 1; }

echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}          Installing MitthuAI for macOS        ${NC}"
echo -e "${BLUE}===============================================${NC}"

# 1. Preflight ---------------------------------------------------------------
say "[1/5] Checking this Mac..."
[ "$(uname -s)" = "Darwin" ] || die "MitthuAI only runs on macOS."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 12 ] 2>/dev/null \
    || die "macOS 12 (Monterey) or newer is required — this Mac runs $(sw_vers -productVersion)."
echo "  macOS $(sw_vers -productVersion) on $(uname -m)"

TEMP_DIR="$(mktemp -d)"
DMG_PATH="${TEMP_DIR}/${APP_NAME}.dmg"
MOUNT_POINT=""

# diskutil grew image subcommands in newer macOS; hdiutil is the fallback.
HAS_DISKUTIL_IMAGE=0
if diskutil 2>&1 | grep -q "image"; then HAS_DISKUTIL_IMAGE=1; fi

cleanup() {
    if [ -n "$MOUNT_POINT" ]; then
        if [ "$HAS_DISKUTIL_IMAGE" = "1" ]; then
            diskutil eject "$MOUNT_POINT" &>/dev/null || true
        else
            hdiutil detach "$MOUNT_POINT" -force &>/dev/null || true
        fi
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# 2. Download ---------------------------------------------------------------
say "[2/5] Downloading ${APP_NAME} (${VERSION})..."
curl -fL --retry 3 -o "$DMG_PATH" "$DMG_URL" --progress-bar \
    || die "download failed: $DMG_URL"

# 3. Verify -----------------------------------------------------------------
say "[3/5] Verifying download..."
if [ -n "${MITTHUAI_DMG_URL:-}" ]; then
    echo "  skipped (custom MITTHUAI_DMG_URL)"
elif SUMS="$(curl -fsSL "$SUMS_URL" 2>/dev/null)" && [ -n "$SUMS" ]; then
    EXPECTED="$(echo "$SUMS" | awk -v f="${APP_NAME}.dmg" '$2 == f || $2 == "*"f {print $1}')"
    ACTUAL="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
    [ -n "$EXPECTED" ] || die "SHA256SUMS.txt has no entry for ${APP_NAME}.dmg."
    [ "$EXPECTED" = "$ACTUAL" ] \
        || die "checksum mismatch — expected ${EXPECTED}, got ${ACTUAL}. Nothing was installed."
    echo "  ✓ sha256 ${ACTUAL}"
else
    warn "  ! no SHA256SUMS.txt published for this release — skipping checksum"
fi

# 4. Install ----------------------------------------------------------------
say "[4/5] Installing to /Applications..."
if [ "$HAS_DISKUTIL_IMAGE" = "1" ]; then
    MOUNT_INFO="$(diskutil image attach --mountOptions nobrowse --readOnly "$DMG_PATH" | grep "/Volumes/")"
else
    MOUNT_INFO="$(hdiutil attach -nobrowse -readonly "$DMG_PATH" 2>/dev/null | grep "/Volumes/")"
fi
MOUNT_POINT="$(echo "$MOUNT_INFO" | awk -F'\t' '{print $NF}' | xargs)"
[ -n "$MOUNT_POINT" ] || die "failed to mount the disk image."

APP_SOURCE="${MOUNT_POINT}/${APP_NAME}.app"
[ -d "$APP_SOURCE" ] || die "${APP_NAME}.app not found inside the disk image."

# Replacing a running app leaves the old binary half-live, so quit it first.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "  quitting the running copy..."
    osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 1
    done
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

DEST="/Applications/${APP_NAME}.app"
if [ -d "$DEST" ]; then
    echo "  replacing the existing installation (your data is untouched)..."
    rm -rf "$DEST" 2>/dev/null || sudo rm -rf "$DEST"
fi

if cp -R "$APP_SOURCE" /Applications/ 2>/dev/null; then
    echo "  ✓ ${DEST}"
else
    say "  Please enter your Mac password to install into /Applications:"
    sudo cp -R "$APP_SOURCE" /Applications/
fi

# 5. Clear quarantine and launch --------------------------------------------
say "[5/5] Clearing the download quarantine flag..."
xattr -cr "$DEST" 2>/dev/null || sudo xattr -cr "$DEST"

open -a "$DEST" >/dev/null 2>&1 || true

INSTALLED="$(defaults read "${DEST}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}   MitthuAI ${INSTALLED} is installed and running 🦜   ${NC}"
echo -e "${BLUE}===============================================${NC}"
cat <<'NEXT'
One more step — capture stays empty until you grant Accessibility:

  System Settings → Privacy & Security → Accessibility → enable MitthuAI,
  then quit MitthuAI from the menu bar (🦜 → Quit) and open it again.

Your data lives in ~/Library/Application Support/MitthuAI/ and survives
updates. Re-run this installer any time to update.
NEXT
