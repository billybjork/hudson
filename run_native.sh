#!/bin/bash
# Hudson Native App Launcher
# Starts the Tauri-wrapped Hudson desktop app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Launching Hudson native app..."

# Set the backend binary path
export HUDSON_BACKEND_BIN="$SCRIPT_DIR/burrito_out/hudson_macos_arm"

# Clean up old handshake file
rm -f /tmp/hudson_port.json

# Launch the native app
exec ./src-tauri/target/release/hudson_desktop
