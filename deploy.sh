#!/bin/bash

# di2steps deployment script for Garmin Edge 1050
# 
# Prerequisites:
# - Garmin ConnectIQ SDK installed
# - SwiftMTP CLI (https://github.com/Neighbor-Z/SwiftMTP)
# - Garmin Edge 1050 connected via USB in MTP mode
# - Dev key at /Users/robert/Certs/garmin_developer_key.der

set -e

SDK_PATH="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"
DEV_KEY="/Users/robert/Certs/garmin_developer_key.der"
PRG_OUTPUT="bin/di2steps.prg"
MONKEY_JUNGLE="monkey.jungle"
# SwiftMTP ships as a sandboxed app; the CLI lives inside the bundle (there is
# no `swiftmtp` on PATH). Device and storage IDs are not invariant, so we
# discover them at deploy time rather than hardcoding.
SWIFTMTP_CLI="/Applications/SwiftMTP.app/Contents/MacOS/swiftmtp-cli"
REMOTE_DIR="/GARMIN/Apps"

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

if [ ! -x "$SWIFTMTP_CLI" ]; then
    echo "Error: swiftmtp-cli not found at $SWIFTMTP_CLI"
    echo "       Install SwiftMTP.app (https://github.com/Neighbor-Z/SwiftMTP)"
    exit 1
fi

# Discover the connected device. `devices` prints tab-separated rows like:
#   2334|20824|0000d837e511<TAB>device<TAB>Edge 1050 (Garmin)
# The pipe-joined first field carries multiple usable IDs; we take the last
# part (the serial), which is the stable, unique one.
echo "Discovering device..."
# MTP enumeration can lag a few seconds after (re)connect, so retry briefly.
device_field=""
for attempt in 1 2 3 4 5; do
    device_field="$("$SWIFTMTP_CLI" devices 2>/dev/null | awk -F'\t' '$2 == "device" { print $1; exit }')"
    [ -n "$device_field" ] && break
    sleep 3
done
if [ -z "$device_field" ]; then
    echo "Error: no MTP device found. Is the Edge 1050 connected, unlocked, and in MTP mode?"
    exit 1
fi
device_id="${device_field##*|}"

# Discover the storage. Prefer "Internal Storage" (where /GARMIN lives); fall
# back to the first listed storage if the label differs.
storage_id="$("$SWIFTMTP_CLI" storages "$device_id" 2>/dev/null | awk -F'\t' '$2 ~ /Internal Storage/ { print $1; exit }')"
if [ -z "$storage_id" ]; then
    storage_id="$("$SWIFTMTP_CLI" storages "$device_id" 2>/dev/null | awk -F'\t' '$1 ~ /^[0-9]+$/ { print $1; exit }')"
fi
if [ -z "$storage_id" ]; then
    echo "Error: no storage found on device $device_id"
    exit 1
fi
echo "  device:  $device_id"
echo "  storage: $storage_id"
echo ""

# swiftmtp-cli push needs an absolute local path and the full remote file path.
local_prg="$(cd "$(dirname "$PRG_OUTPUT")" && pwd)/$(basename "$PRG_OUTPUT")"
remote_prg="$REMOTE_DIR/$(basename "$PRG_OUTPUT")"

# push prompts "Overwrite? [y/n]" when the file already exists; feed 'y' so a
# redeploy is non-interactive (the extra input is harmless on a first push).
# On success it prints "Push complete." — rely on that marker rather than exit
# status. Capture output (guarded from set -e).
push_output="$(printf 'y\n' | "$SWIFTMTP_CLI" push "$device_id" "$storage_id" "$local_prg" "$remote_prg" 2>&1)" || true
echo "$push_output"
if ! printf '%s' "$push_output" | grep -q "Push complete."; then
    echo "Error: push did not report completion"
    exit 1
fi

# Verify the file actually landed.
if "$SWIFTMTP_CLI" ls "$device_id" "$storage_id" "$REMOTE_DIR" 2>/dev/null | grep -q "$(basename "$PRG_OUTPUT")"; then
    echo "✓ Pushed and verified: $remote_prg"
else
    echo "Error: $remote_prg not present after push"
    exit 1
fi
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
