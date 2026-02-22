#!/usr/bin/env bash
set -euo pipefail

BUNDLE="./BusyLight.app"

# Build (and assemble .app bundle) if needed
if [[ ! -d "${BUNDLE}" ]]; then
    echo "[debug.sh] Bundle not found. Building first..."
    bash build.sh
fi

echo "[debug.sh] Launching ${BUNDLE}..."
open "${BUNDLE}"

# Resolve the PID of the running binary inside the bundle
sleep 1
APP_PID=$(pgrep -f "BusyLight.app/Contents/MacOS/BusyLight" | head -1 || true)
if [[ -n "$APP_PID" ]]; then
    echo "[debug.sh] PID: $APP_PID"
else
    echo "[debug.sh] Could not resolve PID (app may have already been running)"
fi

echo "[debug.sh] Streaming logs (Ctrl+C to stop)..."
echo "--------------------------------------------------------------"

cleanup() {
    echo ""
    if [[ -n "${APP_PID:-}" ]]; then
        echo "[debug.sh] Stopping BusyLight (PID $APP_PID)..."
        kill "$APP_PID" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup INT TERM

# Stream all BusyLight subsystems to stdout
log stream \
    --predicate 'subsystem BEGINSWITH "com.busylight.agent"' \
    --level debug \
    --style compact
