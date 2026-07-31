#!/bin/bash

# di2steps deployment script for Garmin Edge 1050
#
# Prerequisites:
# - Garmin ConnectIQ SDK installed
# - SwiftMTP CLI at /Applications/SwiftMTP.app/Contents/MacOS/swiftmtp-cli
# - Garmin Edge 1050 connected via USB in MTP mode
# - Dev key at /Users/robert/Certs/garmin_developer_key.der

set -e

SDK_PATH="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
DEV_KEY="/Users/robert/Certs/garmin_developer_key.der"
SWIFTMTP="/Applications/SwiftMTP.app/Contents/MacOS/swiftmtp-cli"
PRG_OUTPUT="bin/di2steps.prg"
MONKEY_JUNGLE="monkey.jungle"

echo "=== di2steps Deploy ==="
echo ""

# Step 1: Build
echo "Step 1: Building..."
if [ ! -f "$MONKEY_JUNGLE" ]; then
    echo "Error: $MONKEY_JUNGLE not found"
    exit 1
fi

if [ ! -f "$DEV_KEY" ]; then
    echo "Error: Dev key not found at $DEV_KEY"
    exit 1
fi

if [ ! -f "$SWIFTMTP" ]; then
    echo "Error: SwiftMTP CLI not found at $SWIFTMTP"
    exit 1
fi

mkdir -p bin
"$SDK_PATH/bin/monkeyc" -d edge1050 -f "$MONKEY_JUNGLE" -o "$PRG_OUTPUT" -y "$DEV_KEY"
echo "✓ Built: $PRG_OUTPUT"
echo ""

# Step 2: Discover device
echo "Step 2: Detecting Edge 1050..."
DEVICES=$("$SWIFTMTP" devices 2>&1 | grep "Edge 1050")
if [ -z "$DEVICES" ]; then
    echo "Error: Edge 1050 not found. Make sure it's connected in MTP mode and unlocked."
    exit 1
fi
DEVICE_ID=$(echo "$DEVICES" | cut -d'|' -f3)
STORAGE_ID="65537"
echo "✓ Found device: $DEVICE_ID"
echo ""

# Step 3: Deploy
echo "Step 3: Deploying to Edge 1050 via SwiftMTP..."
echo ""

# Remove old version if it exists
if echo -e "y" | "$SWIFTMTP" rm -r "$DEVICE_ID" "$STORAGE_ID" /GARMIN/Apps/di2steps.prg 2>/dev/null; then
    echo "✓ Removed old version"
fi

# Push new version
PRG_FULL_PATH="$(pwd)/$PRG_OUTPUT"
echo -e "Pushing $(basename "$PRG_OUTPUT") to device..."
"$SWIFTMTP" push "$DEVICE_ID" "$STORAGE_ID" "$PRG_FULL_PATH" /GARMIN/Apps/
echo "✓ Deployment complete"
echo ""

# Step 4: Instructions
echo "Next steps:"
echo "  1. Disconnect the Edge 1050 from USB"
echo "  2. Restart the Edge 1050 device"
echo "  3. The di2steps data field should now be available"
echo ""
echo "To validate:"
echo "  - Set DisplayMode = 2 (Test/Diagnostics) in app settings"
echo "  - Check connection status and data flow in Test screen"
echo ""
echo "=== Deploy Complete ==="
