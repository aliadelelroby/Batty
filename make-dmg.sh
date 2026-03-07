#!/bin/bash
# make-dmg.sh — builds a distributable Batty.dmg
#
# Usage:
#   bash make-dmg.sh
#
# Output:
#   dist/Batty.dmg
#
# Requirements:
#   - Swift Package Manager (xcode-select --install)
#   - hdiutil (ships with macOS)
#   - No external tools needed
#
set -e

APP_NAME="Batty"
BUNDLE_ID="com.batty.app"
VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
STAGING_DIR="$DIST_DIR/staging"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
DMG_OUT="$DIST_DIR/$APP_NAME.dmg"
DMG_TMP="$DIST_DIR/${APP_NAME}_tmp.dmg"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}  ! $1${NC}"; }
die()  { echo -e "${RED}ERROR: $1${NC}"; exit 1; }

echo ""
echo "  Batty DMG Builder"
echo "  ──────────────────"
echo ""

# ── 1. Build ─────────────────────────────────────────────────────────────────
log "Building release binary…"
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | grep -E "error:|Build complete|Compiling|Linking" || true
[ -f ".build/release/$APP_NAME" ] || die "Build failed — binary not found"
log "Build complete."

# ── 2. Assemble app bundle ────────────────────────────────────────────────────
log "Assembling app bundle…"
rm -rf "$STAGING_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>              <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>             <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                   <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>            <string>$APP_NAME</string>
    <key>CFBundleVersion</key>                <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>     <string>$VERSION</string>
    <key>CFBundlePackageType</key>            <string>APPL</string>
    <key>CFBundleSignature</key>              <string>????</string>
    <key>LSUIElement</key>                    <true/>
    <key>NSHighResolutionCapable</key>        <true/>
    <key>LSMinimumSystemVersion</key>         <string>13.0</string>
    <key>NSSupportsAutomaticTermination</key> <false/>
    <key>NSSupportsSuddenTermination</key>    <false/>
</dict>
</plist>
PLIST

cp ".build/release/$APP_NAME"        "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Sources/Batty/Resources/smc"     "$APP_BUNDLE/Contents/Resources/smc"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/Resources/smc"

# Copy app icon if it exists
if [ -f "Sources/Batty/Resources/AppIcon.icns" ]; then
    cp "Sources/Batty/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
fi

log "App bundle assembled at $APP_BUNDLE"

# ── 3. Create DMG ─────────────────────────────────────────────────────────────
log "Creating DMG…"
mkdir -p "$DIST_DIR"
rm -f "$DMG_OUT" "$DMG_TMP"

# Create a read/write image to set it up
hdiutil create \
    -srcfolder "$STAGING_DIR" \
    -volname "$APP_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,b=16" \
    -format UDRW \
    -size 60m \
    "$DMG_TMP" > /dev/null

# Mount it
DEVICE=$(hdiutil attach -readwrite -noverify "$DMG_TMP" | grep "^/dev/" | awk '{print $1}' | head -1)
MOUNT_PATH="/Volumes/$APP_NAME"

# Wait for mount
sleep 1

# Create Applications symlink
ln -sf /Applications "$MOUNT_PATH/Applications"

# Optional: set DMG window layout via AppleScript (best effort)
osascript <<OSASCRIPT 2>/dev/null || true
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 660, 420}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set position of item "$APP_NAME.app" of container window to {160, 170}
        set position of item "Applications" of container window to {400, 170}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
OSASCRIPT

# Unmount
sync
hdiutil detach "$DEVICE" > /dev/null

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_OUT" > /dev/null

rm -f "$DMG_TMP"
rm -rf "$STAGING_DIR"

log "DMG created: $DMG_OUT"
echo ""
echo -e "  ${GREEN}Done!${NC} Distribute dist/Batty.dmg"
echo "  Users: open the DMG, drag Batty → Applications, then launch Batty."
echo "  Batty will guide them through the one-time permission on first launch."
echo ""
