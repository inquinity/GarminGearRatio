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
MANIFEST="manifest.xml"
# SwiftMTP ships as a sandboxed app; the CLI lives inside the bundle (there is
# no `swiftmtp` on PATH). Device and storage IDs are not invariant, so we
# discover them at deploy time rather than hardcoding.
SWIFTMTP_CLI="/Applications/SwiftMTP.app/Contents/MacOS/swiftmtp-cli"
REMOTE_DIR="/GARMIN/Apps"
# Seconds to wait before retrying a push that failed to open an MTP session.
# Short waits (under ~10s) were observed not to be enough.
PUSH_COOLDOWN=30

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
# Report the app version being built. The Edge only updates an installed app
# when this manifest version increases (same UUID), so surfacing it here makes
# it obvious whether the build will land as an update on device.
app_version="$(awk -F'version="' '/<iq:application/ { split($2, a, "\""); print a[1]; exit }' "$MANIFEST")"
echo "App version: ${app_version:-<unset>}"
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

# swiftmtp-cli push needs an absolute local path, and treats <remotePath> as the
# destination DIRECTORY — it drops the file in under its own basename, creating
# that path as a directory if it doesn't exist.
#
# Passing the full remote FILE path here is what broke deploys from 2026-07-31
# to 2026-08-09: it created a directory `/GARMIN/Apps/di2steps.prg/` and wrote
# the real .prg inside it. The Edge scans /GARMIN/Apps for .prg *files*, saw a
# directory, and skipped it — so the field never appeared however many times we
# "successfully" pushed. Pass the directory. See ERRORS.md.
local_prg="$(cd "$(dirname "$PRG_OUTPUT")" && pwd)/$(basename "$PRG_OUTPUT")"
prg_name="$(basename "$PRG_OUTPUT")"
remote_prg="$REMOTE_DIR/$prg_name"
expected_size="$(wc -c < "$local_prg" | tr -d '[:space:]')"

# push prompts "Overwrite? [y/n]" when the file already exists; feed 'y' so a
# redeploy is non-interactive (the extra input is harmless on a first push).
# On success it prints "Push complete." — rely on that marker rather than exit
# status. Capture output (guarded from set -e).
#
# The Edge frequently refuses to open an MTP session even though it enumerates
# fine — the failure looks like "OpenSession failed: LIBUSB_ERROR_IO" or
# "fatal error LIBUSB_ERROR_IO", and swiftmtp's own auto-reset often doesn't
# recover it. Enumerating successfully above says nothing about whether a
# session will open. It is frequently transient, so retry with a real cooldown
# rather than failing on the first attempt. See ERRORS.md.
push_output=""
push_ok=0
for attempt in 1 2 3; do
    if [ "$attempt" -gt 1 ]; then
        echo "  session failed; cooling down ${PUSH_COOLDOWN}s before retry $attempt/3..."
        sleep "$PUSH_COOLDOWN"
    fi
    push_output="$(printf 'y\n' | "$SWIFTMTP_CLI" push "$device_id" "$storage_id" "$local_prg" "$REMOTE_DIR" 2>&1)" || true
    echo "$push_output"
    if printf '%s' "$push_output" | grep -q "Push complete."; then
        push_ok=1
        break
    fi
    # Anything that isn't a USB session failure won't be fixed by waiting.
    if ! printf '%s' "$push_output" | grep -q "LIBUSB_ERROR_IO"; then
        break
    fi
done

if [ "$push_ok" -ne 1 ]; then
    echo ""
    echo "Error: push did not report completion"
    if printf '%s' "$push_output" | grep -q "LIBUSB_ERROR_IO"; then
        echo "       The device enumerated but would not open an MTP session."
        echo "       Restart the Edge, then reconnect with the screen awake and"
        echo "       unlocked, and keep it awake for the transfer. See ERRORS.md."
        echo "       Ignore any 'occupied by other processes, PID: N' line — those"
        echo "       PIDs are routinely stale and have sent us chasing ghosts."
    fi
    exit 1
fi

# Verify the file actually landed, as a FILE of the expected SIZE.
#
# A bare `grep -q di2steps.prg` on the listing is not good enough: it matched a
# stray *directory* of that name for nine days and reported "verified" on every
# deploy while the app was never installed. `ls` renders directories as "<DIR>"
# in the size column, so compare the size field instead of matching the name.
#
# This opens another session immediately after the push, which is exactly when
# the device is most likely to refuse one, so a listing failure is NOT evidence
# the push failed — report that as unverified rather than as an error.
listing="$("$SWIFTMTP_CLI" ls "$device_id" "$storage_id" "$REMOTE_DIR" 2>/dev/null)" || true
remote_size="$(printf '%s\n' "$listing" | awk -v name="$prg_name" '$NF == name { print $1; exit }')"

if [ "$remote_size" = "$expected_size" ]; then
    echo "✓ Pushed and verified: $remote_prg ($expected_size bytes)"
elif [ "$remote_size" = "<DIR>" ]; then
    echo "Error: $remote_prg is a DIRECTORY, not a file."
    echo "       The Edge only loads .prg *files* from $REMOTE_DIR, so the app"
    echo "       will not appear however many times you restart it. Remove it:"
    echo "         $SWIFTMTP_CLI rm -r $device_id $storage_id $remote_prg"
    echo "       then re-run this script."
    exit 1
elif [ -z "$remote_size" ]; then
    echo "✓ Pushed: $remote_prg"
    echo "  (could not re-list $REMOTE_DIR to verify — the push itself reported"
    echo "   completion, so this is most likely the device declining a second"
    echo "   back-to-back session, not a failed transfer)"
else
    echo "Error: $remote_prg is $remote_size bytes, expected $expected_size"
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
