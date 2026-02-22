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
