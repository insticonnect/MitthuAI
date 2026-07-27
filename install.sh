#!/bin/bash
set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}          Installing MitthuAI for macOS          ${NC}"
echo -e "${BLUE}===============================================${NC}"

# Temporary download locations
APP_NAME="MitthuAI"
DMG_URL="${MITTHUAI_DMG_URL:-https://github.com/insticonnect/MitthuAI/releases/latest/download/MitthuAI.dmg}"
TEMP_DIR=$(mktemp -d)
DMG_PATH="${TEMP_DIR}/${APP_NAME}.dmg"
MOUNT_POINT=""

# 1. Download DMG
echo -e "${BLUE}[1/4] Downloading latest ${APP_NAME}.dmg...${NC}"
curl -L -o "$DMG_PATH" "$DMG_URL" --progress-bar

# 2. Mount DMG
echo -e "${BLUE}[2/4] Mounting disk image...${NC}"
# Use diskutil image attach if supported, fallback to hdiutil attach
if diskutil 2>&1 | grep -q "image"; then
    MOUNT_INFO=$(diskutil image attach --mountOptions nobrowse --readOnly "$DMG_PATH" | grep "/Volumes/")
else
    # Fallback for older macOS versions
    MOUNT_INFO=$(hdiutil attach -nobrowse -readonly "$DMG_PATH" 2>/dev/null | grep "/Volumes/")
fi
MOUNT_POINT=$(echo "$MOUNT_INFO" | awk -F'\t' '{print $NF}' | xargs)

if [ -z "$MOUNT_POINT" ]; then
    echo -e "${RED}Error: Failed to mount DMG.${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup handler to unmount DMG in case of failure
cleanup() {
    if [ -n "$MOUNT_POINT" ]; then
        if diskutil 2>&1 | grep -q "image"; then
            diskutil eject "$MOUNT_POINT" &>/dev/null || true
        else
            hdiutil detach "$MOUNT_POINT" -force &>/dev/null || true
        fi
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# 3. Copy Application
echo -e "${BLUE}[3/4] Installing ${APP_NAME}.app to Applications folder...${NC}"
APP_SOURCE="${MOUNT_POINT}/${APP_NAME}.app"

if [ -d "/Applications/${APP_NAME}.app" ]; then
    echo "Updating existing installation of ${APP_NAME}..."
    rm -rf "/Applications/${APP_NAME}.app"
fi

# Try copying. If permission fails, try with sudo.
if cp -R "$APP_SOURCE" "/Applications/" 2>/dev/null; then
    echo "Successfully copied ${APP_NAME}.app."
else
    echo -e "${BLUE}Please enter your Mac password to complete the installation:${NC}"
    sudo cp -R "$APP_SOURCE" "/Applications/"
fi

# 4. De-quarantine
echo -e "${BLUE}[4/4] Removing Gatekeeper security restrictions...${NC}"
if xattr -cr "/Applications/${APP_NAME}.app" 2>/dev/null; then
    :
else
    sudo xattr -cr "/Applications/${APP_NAME}.app"
fi

echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}      Success! MitthuAI is installed.              ${NC}"
echo -e "${BLUE}===============================================${NC}"
echo "You can now open MitthuAI from your Applications folder."
