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

# Step 2: Deploy
echo "Step 2: Deploying to Edge 1050 via SwiftMTP..."
echo ""
echo "Make sure your Edge 1050 is:"
echo "  1. Connected to USB"
echo "  2. In MTP mode (not Garmin Basemap mode)"
echo "  3. Unlocked"
echo ""

"$SWIFTMTP" push "$PRG_OUTPUT" /GARMIN/Apps
echo "✓ Pushed to device"
echo ""

# Step 3: Complete
echo "Step 3: Finalizing..."
echo ""
echo "Next steps:"
echo "  1. Disconnect the Edge 1050 from USB"
echo "  2. Restart the Edge 1050 device"
echo "  3. The data field should now be available"
echo ""
echo "To test:"
echo "  - Set DisplayMode = 2 (Test/Diagnostics) in app settings"
echo "  - Check connection status and data flow in Test screen"
echo ""
echo "=== Deploy Complete ==="
