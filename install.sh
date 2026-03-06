#!/bin/bash
set -e

APP_NAME="Batty"
APP_BUNDLE="/Applications/Batty.app"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Batty"
SMC_BINARY="$APP_BUNDLE/Contents/Resources/smc"
SUDOERS_FILE="/etc/sudoers.d/batty"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}  ! $1${NC}"; }
die()  { echo -e "${RED}ERROR: $1${NC}"; exit 1; }

echo ""
echo "  Batty Installer"
echo "  ────────────────"
echo ""

# ── 1. Uninstall existing ────────────────────────────────────────────────────
log "Stopping Batty…"
pkill -x Batty 2>/dev/null && sleep 0.5 || true

log "Removing previous install…"
sudo rm -f "$SUDOERS_FILE"
sudo rm -rf "$APP_BUNDLE"
rm -rf ~/Library/Preferences/com.batty.app.plist 2>/dev/null || true
# Clear any other bundle-ID variants
for f in ~/Library/Preferences/*atty*.plist; do
    [ -f "$f" ] && rm -f "$f" && warn "Removed $f"
done

# ── 2. Build ─────────────────────────────────────────────────────────────────
log "Building Batty (release)…"
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | grep -E "error:|warning:|Build complete|Compiling|Linking" || true
[ -f ".build/release/Batty" ] || die "Build failed — binary not found at .build/release/Batty"
log "Build complete."

# ── 3. Create app bundle ─────────────────────────────────────────────────────
log "Creating app bundle at $APP_BUNDLE…"
sudo mkdir -p "$APP_BUNDLE/Contents/MacOS"
sudo mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist if exists, otherwise write a minimal one
if [ -f "$SCRIPT_DIR/Sources/Batty/Resources/Info.plist" ]; then
    sudo cp "$SCRIPT_DIR/Sources/Batty/Resources/Info.plist" "$APP_BUNDLE/Contents/"
else
    sudo tee "$APP_BUNDLE/Contents/Info.plist" > /dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>     <string>Batty</string>
    <key>CFBundleIdentifier</key>     <string>com.batty.app</string>
    <key>CFBundleName</key>           <string>Batty</string>
    <key>CFBundleVersion</key>        <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSUIElement</key>            <true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key> <string>13.0</string>
</dict>
</plist>
PLIST
fi

sudo cp ".build/release/Batty"              "$EXECUTABLE"
sudo cp "Sources/Batty/Resources/smc"       "$SMC_BINARY"
sudo chmod +x "$EXECUTABLE" "$SMC_BINARY"
log "App bundle ready."

# ── 4. Install sudoers entry (passwordless sudo for smc) ────────────────────
log "Installing sudoers entry (requires admin password)…"
CURRENT_USER="$(whoami)"
SUDOERS_LINE="${CURRENT_USER} ALL=(ALL) NOPASSWD: ${SMC_BINARY} *"

# Validate with visudo before installing
TMPFILE="$(mktemp /tmp/batty_sudoers_XXXXXX)"
echo "$SUDOERS_LINE" > "$TMPFILE"
sudo visudo -c -f "$TMPFILE" > /dev/null 2>&1 || die "Generated sudoers line failed visudo check"
sudo cp "$TMPFILE" "$SUDOERS_FILE"
sudo chmod 440 "$SUDOERS_FILE"
sudo chown root:wheel "$SUDOERS_FILE"
rm -f "$TMPFILE"
log "Sudoers entry installed → $SUDOERS_FILE"

# ── 5. Verify sudo works without password ───────────────────────────────────
log "Verifying passwordless sudo smc…"
if sudo "$SMC_BINARY" -k CHTE -r > /dev/null 2>&1; then
    log "Verification passed — CHTE readable as root."
else
    warn "Verification read failed (smc exit non-zero). Will attempt writes anyway."
fi

# ── 6. Test: disable charging, wait 2s, re-enable ───────────────────────────
log "Testing charge control (disabling for 2 seconds)…"
if sudo "$SMC_BINARY" -k CHTE -w 01000000 2>/dev/null; then
    log "Charging disabled (CHTE = 01000000) ✓"
    sleep 2
    sudo "$SMC_BINARY" -k CHTE -w 00000000 2>/dev/null && log "Charging re-enabled (CHTE = 00000000) ✓" || warn "Re-enable failed"
else
    warn "CHTE write failed — SMC write not permitted on this Mac?"
fi

# ── 7. Launch ────────────────────────────────────────────────────────────────
log "Launching Batty…"
open "$APP_BUNDLE"
sleep 1

echo ""
echo -e "  ${GREEN}Done!${NC} Batty is running in the menu bar."
echo "  The sudoers entry is permanent — no future admin prompts needed."
echo "  To uninstall: sudo rm /etc/sudoers.d/batty && sudo rm -rf /Applications/Batty.app"
echo ""
