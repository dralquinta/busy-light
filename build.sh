#!/usr/bin/env bash
# build.sh — Builds the BusyLight macOS agent from the project root.
# Tests are skipped automatically when running outside a full Xcode environment
# (Swift Testing's Foundation cross-import overlay is not available in CLT).
#
# Usage:
#   ./build.sh               # Debug build
#   ./build.sh release       # Release build
#   ./build.sh test          # Run tests (requires full Xcode install)
#   ./build.sh clean         # Remove .build directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$SCRIPT_DIR/macos-agent"
CONFIG="${1:-debug}"

# ── Helpers ─────────────────────────────────────────────────────────────────

log()  { echo "[build.sh] $*"; }
fail() { echo "[build.sh] ERROR: $*" >&2; exit 1; }

require_swift() {
    command -v swift &>/dev/null || fail "Swift not found. Install Xcode or Command Line Tools."
    log "Using $(swift --version 2>&1 | head -1)"
}

xcode_available() {
    command -v xcodebuild &>/dev/null && \
        xcode-select -p &>/dev/null 2>&1 && \
        [[ "$(xcode-select -p)" != *"CommandLineTools"* ]]
}

# ── Actions ──────────────────────────────────────────────────────────────────

do_build() {
    local cfg="$1"
    log "Building BusyLight ($cfg)…"
    cd "$AGENT_DIR"
    if [[ "$cfg" == "release" ]]; then
        swift build -c release
    else
        swift build
    fi
    log "Build succeeded → $AGENT_DIR/.build/$cfg/BusyLight"
    do_bundle "$cfg"
}

# Assembles a proper .app bundle so macOS TCC shows the calendar permission
# prompt.  Without a bundle + embedded Info.plist the system silently denies
# calendar access and never presents a dialog.
do_bundle() {
    local cfg="$1"
    local binary="$AGENT_DIR/.build/$cfg/BusyLight"
    local bundle="$SCRIPT_DIR/BusyLight.app"
    local plist="$AGENT_DIR/Sources/BusyLight/Resources/Info.plist"
    local icon_png="$SCRIPT_DIR/img/busy-light-icon.png"

    log "Assembling ${bundle}..."
    rm -rf "$bundle"
    mkdir -p "$bundle/Contents/MacOS"
    mkdir -p "$bundle/Contents/Resources"
    
    cp "$binary" "$bundle/Contents/MacOS/BusyLight"
    cp "$plist"   "$bundle/Contents/Info.plist"

    # Convert PNG icon to ICNS and add to bundle
    if [[ -f "$icon_png" ]]; then
        log "Converting app icon to ICNS format..."
        local temp_iconset="/tmp/BusyLight.iconset"
        rm -rf "$temp_iconset"
        mkdir -p "$temp_iconset"
        
        # Create required icon sizes for macOS
        sips -z 16 16     "$icon_png" --out "$temp_iconset/icon_16x16.png" &>/dev/null
        sips -z 32 32     "$icon_png" --out "$temp_iconset/icon_16x16@2x.png" &>/dev/null
        sips -z 32 32     "$icon_png" --out "$temp_iconset/icon_32x32.png" &>/dev/null
        sips -z 64 64     "$icon_png" --out "$temp_iconset/icon_32x32@2x.png" &>/dev/null
        sips -z 128 128   "$icon_png" --out "$temp_iconset/icon_128x128.png" &>/dev/null
        sips -z 256 256   "$icon_png" --out "$temp_iconset/icon_128x128@2x.png" &>/dev/null
        sips -z 256 256   "$icon_png" --out "$temp_iconset/icon_256x256.png" &>/dev/null
        sips -z 512 512   "$icon_png" --out "$temp_iconset/icon_256x256@2x.png" &>/dev/null
        sips -z 512 512   "$icon_png" --out "$temp_iconset/icon_512x512.png" &>/dev/null
        sips -z 1024 1024 "$icon_png" --out "$temp_iconset/icon_512x512@2x.png" &>/dev/null
        
        if command -v iconutil &>/dev/null; then
            iconutil -c icns "$temp_iconset" -o "$bundle/Contents/Resources/AppIcon.icns" 2>/dev/null
            log "App icon created: AppIcon.icns"
        else
            log "Warning: iconutil not found, app will not have an icon"
        fi
        
        rm -rf "$temp_iconset"
    else
        log "Warning: Icon not found at $icon_png"
    fi

    # Ad-hoc codesign so Gatekeeper and TCC accept the bundle.
    codesign --force --deep --sign - "$bundle" 2>/dev/null && \
        log "Ad-hoc codesign applied." || \
        log "codesign skipped (not critical for local dev)."

    log "Bundle ready -> ${bundle}"
}

do_test() {
    cd "$AGENT_DIR"
    if xcode_available; then
        log "Xcode detected — running tests with xcodebuild…"
        xcodebuild test -scheme BusyLight 2>&1
    else
        log "Xcode not available (Command Line Tools only)."
        log "Swift Testing requires the full Xcode installation."
        log "Skipping tests."
        exit 0
    fi
}

do_clean() {
    log "Cleaning build artefacts…"
    cd "$AGENT_DIR"
    rm -rf .build
    rm -rf "$SCRIPT_DIR/BusyLight.app"
    log "Clean complete."
}

# ── Entry point ───────────────────────────────────────────────────────────────

require_swift

case "$CONFIG" in
    debug)                       do_build debug ;;
    release)                     do_build release ;;
    test)                        do_test ;;
    clean)                       do_clean ;;
    *)
        fail "Unknown command: $CONFIG. Valid commands: debug | release | test | clean"
        ;;
esac
