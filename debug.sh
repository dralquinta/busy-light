#!/usr/bin/env bash
set -euo pipefail

BINARY="./macos-agent/.build/debug/BusyLight"

if [[ ! -x "$BINARY" ]]; then
    echo "[debug.sh] Binary not found. Building first…"
    bash build.sh
fi

echo "[debug.sh] Starting BusyLight…"
"$BINARY" &
APP_PID=$!
echo "[debug.sh] PID: $APP_PID"

# Give the app a moment to register its subsystem
sleep 1

echo "[debug.sh] Streaming logs (Ctrl+C to stop app + log stream)…"
echo "──────────────────────────────────────────────────────────────"

cleanup() {
    echo ""
    echo "[debug.sh] Stopping BusyLight (PID $APP_PID)…"
    kill "$APP_PID" 2>/dev/null || true
    exit 0
}
trap cleanup INT TERM

# Stream all BusyLight subsystems to stdout
log stream \
    --predicate 'subsystem BEGINSWITH "com.busylight.agent"' \
    --level debug \
    --style compact
