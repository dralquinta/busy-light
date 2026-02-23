#!/usr/bin/env bash
# create-dmg-background.sh — Create a professional DMG background image
#
# This script generates a background image for the DMG installer
# with installation instructions and branding

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$PROJECT_ROOT/img/dmg-background.png"
ICON_FILE="$PROJECT_ROOT/img/busy-light-icon.png"

# Check if ImageMagick is available
if ! command -v convert &>/dev/null; then
    echo "ImageMagick not found. Creating a simple background..."
    echo "For a professional background, install ImageMagick:"
    echo "  brew install imagemagick"
    
    # Create a simple gradient background using native tools
    if command -v sips &>/dev/null; then
        # Create a basic solid color background
        # Note: This is a fallback - for production, use ImageMagick
        echo "Using basic fallback method..."
        # Copy and resize icon as a placeholder
        if [[ -f "$ICON_FILE" ]]; then
            sips -z 400 600 "$ICON_FILE" --out "$OUTPUT_FILE" &>/dev/null || true
        fi
    fi
    
    exit 0
fi

echo "Creating DMG background image..."

# DMG window size (standard size)
WIDTH=600
HEIGHT=400

# Create gradient background
convert -size ${WIDTH}x${HEIGHT} \
    gradient:#e8f4f8-#b8dae8 \
    "$OUTPUT_FILE"

# Add subtle pattern/texture
convert "$OUTPUT_FILE" \
    -alpha set -channel A -evaluate set 95% \
    "$OUTPUT_FILE"

# Add text instructions
convert "$OUTPUT_FILE" \
    -gravity center \
    -pointsize 24 \
    -font "Helvetica-Bold" \
    -fill "#2c3e50" \
    -annotate +0-120 "BusyLight" \
    "$OUTPUT_FILE"

convert "$OUTPUT_FILE" \
    -gravity center \
    -pointsize 14 \
    -font "Helvetica" \
    -fill "#34495e" \
    -annotate +0-90 "macOS Presence Indicator" \
    "$OUTPUT_FILE"

# Add installation instruction arrow and text
convert "$OUTPUT_FILE" \
    -gravity center \
    -pointsize 16 \
    -font "Helvetica" \
    -fill "#555555" \
    -annotate +0+140 "Drag the app to Applications to install" \
    "$OUTPUT_FILE"

# Add a subtle arrow (using text as fallback)
convert "$OUTPUT_FILE" \
    -gravity center \
    -pointsize 40 \
    -font "Helvetica-Bold" \
    -fill "#3498db" \
    -annotate +0+100 "→" \
    "$OUTPUT_FILE"

echo "✓ DMG background created: $OUTPUT_FILE"
echo "  Size: $(du -h "$OUTPUT_FILE" | cut -f1)"

# Preview (if on macOS with GUI)
if [[ "$OSTYPE" == "darwin"* ]] && command -v open &>/dev/null; then
    echo ""
    read -p "Preview the background? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "$OUTPUT_FILE"
    fi
fi
