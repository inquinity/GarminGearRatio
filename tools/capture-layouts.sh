#!/bin/bash
#
# capture-layouts.sh — screenshot the running Connect IQ simulator once per
# data-field layout.
#
# The simulator offers 24 data-field layouts on the Edge 1050, each giving the
# field a different slot size. Checking a layout change by hand means 24 menu
# trips; this walks them and leaves a directory of PNGs you can flip through.
#
# Requires:
#   - the CIQ simulator already running with an app loaded (monkeydo ...)
#   - Accessibility permission for whatever runs this (System Events drives the
#     menus), and Screen Recording permission for screencapture
#
# The simulator is brought to the front before each capture: screencapture's
# region mode grabs whatever is topmost, so an overlapping window would
# otherwise end up in the shot.

set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

PROCESS_NAME="simulator"
output_dir="captures/$(date +%Y%m%d-%H%M%S)"
poll_seconds=0.25
timeout_seconds=6
dry_run=0
capture_all=0
only_pattern=""

# Minimum set of layouts that still exercises every distinct slot size on the
# Edge 1050 — 10 of the 24, so a review run is well under half the captures.
#
# Derived (not guessed) from the device's own geometry in
#   ~/Library/Application Support/Garmin/ConnectIQ/Devices/edge1050/simulator.json
# by solving the set-cover exactly over the 17 distinct field sizes. Seven of
# these are forced: each owns a size no other layout offers. The last three
# exist only to reach 239x160, 239x162 and 480x160.
#
#   1 Field      480x800
#   2 Fields     480x399
#   3 Fields A   480x265, 480x266
#   3 Fields B   480x159, 480x318, 480x319
#   3 Fields C   480x160, 480x318
#   4 Fields A   480x198, 480x200
#   4 Fields B   239x159, 480x318, 480x319
#   4 Fields C   239x160, 480x318
#   5 Fields B   239x158, 480x158, 480x162, 480x316
#   5 Fields C   239x162, 480x158, 480x316
#
# To regenerate after an SDK update, re-solve the cover against that JSON.
# Anything not listed here renders at a size one of these already covers.
COVERAGE_LAYOUTS="1 Field
2 Fields
3 Fields A
3 Fields B
3 Fields C
4 Fields A
4 Fields B
4 Fields C
5 Fields B
5 Fields C"

usage() {
    cat <<'USAGE'
Usage: tools/capture-layouts.sh [options]

Steps the running CIQ simulator through data-field layouts and saves a PNG of
the simulator window for each one.

By default it captures only the 10 layouts needed to cover every distinct field
size (of 24 total) — the rest render at a size one of those already shows. Use
--all for the complete set.

Each capture is verified before it is saved: the script confirms the simulator
marked the layout as active, then waits for the rendered window to actually
change. A fixed pause is not enough — the menu updates instantly while the
redraw lags, so a naive script saves the PREVIOUS layout under the new name.

Options:
  -a, --all           Capture all 24 layouts, not just the covering set
  -o, --output DIR    Directory for PNGs (default: captures/<timestamp>)
  -m, --match GLOB    Only layouts whose name matches, e.g. '1 Field' or '*B'
  -p, --poll SECS     Interval between redraw checks (default 0.25)
  -t, --timeout SECS  Give up waiting for a redraw after this (default 6)
  -n, --dry-run       List the layouts that would be captured, change nothing
  -h, --help          Show this help

Examples:
  tools/capture-layouts.sh                 # 10 covering layouts
  tools/capture-layouts.sh --all           # all 24
  tools/capture-layouts.sh --match '1 Field' --output /tmp/one
  tools/capture-layouts.sh --dry-run
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--all)     capture_all=1; shift ;;
        -o|--output)  output_dir="$2"; shift 2 ;;
        -m|--match)   only_pattern="$2"; shift 2 ;;
        -p|--poll)    poll_seconds="$2"; shift 2 ;;
        -t|--timeout) timeout_seconds="$2"; shift 2 ;;
        -n|--dry-run) dry_run=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) print_colored "$COLOR_RED" "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ── Preflight ────────────────────────────────────────────────────────────────

if ! pgrep -f "ConnectIQ.app/Contents/MacOS/$PROCESS_NAME" >/dev/null 2>&1; then
    print_colored "$COLOR_RED" "The Connect IQ simulator is not running."
    print_colored "$COLOR_YELLOW" "  Start it, then load an app:"
    print_colored "$COLOR_YELLOW" "    open \"\$SDK/bin/ConnectIQ.app\""
    print_colored "$COLOR_YELLOW" "    \"\$SDK/bin/monkeydo\" bin/your.prg edge1050"
    exit 1
fi

# Ask the simulator for its own layout list rather than hardcoding one, so this
# keeps working on other devices, which offer different layout sets.
layout_list="$(osascript <<'EOF' 2>/dev/null || true
tell application "System Events"
  tell process "simulator"
    set out to ""
    repeat with i in menu items of menu 1 of menu item "Layout" of menu 1 of menu bar item "Data Fields" of menu bar 1
      set out to out & name of i & "\n"
    end repeat
    return out
  end tell
end tell
EOF
)"

if [ -z "$layout_list" ]; then
    print_colored "$COLOR_RED" "Could not read the Data Fields > Layout menu."
    print_colored "$COLOR_YELLOW" "  Most likely Accessibility permission is missing for the app running"
    print_colored "$COLOR_YELLOW" "  this script. Grant it in System Settings > Privacy & Security >"
    print_colored "$COLOR_YELLOW" "  Accessibility, then retry."
    exit 1
fi

# Unless --all, reduce to the covering set. Every name is checked against the
# menu first: on another device (different layout names) the intersection would
# be wrong, so fall back to capturing everything rather than silently missing
# sizes.
if [ "$capture_all" -eq 0 ]; then
    covering=""
    missing=0
    while IFS= read -r want; do
        [ -z "$want" ] && continue
        if printf '%s\n' "$layout_list" | grep -qxF "$want"; then
            covering="$covering$want"$'\n'
        else
            missing=1
        fi
    done <<< "$COVERAGE_LAYOUTS"

    if [ "$missing" -eq 1 ]; then
        print_colored "$COLOR_YELLOW" "This device's layouts don't match the known covering set; capturing all."
    else
        layout_list="$covering"
    fi
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

select_layout() {
    local layout_name=$1
    osascript <<EOF >/dev/null
tell application "System Events"
  tell process "$PROCESS_NAME"
    set frontmost to true
    click menu item "$layout_name" of menu 1 of menu item "Layout" of menu 1 of menu bar item "Data Fields" of menu bar 1
  end tell
end tell
EOF
}

# Position and size of the simulator window, as "x,y,w,h" for screencapture -R.
window_region() {
    osascript <<EOF 2>/dev/null
tell application "System Events"
  tell process "$PROCESS_NAME"
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
  end tell
end tell
EOF
}

# Name of the layout the simulator currently has checked. This is authoritative
# for "did the click register", but says nothing about whether the window has
# repainted yet — the mark flips immediately, the redraw does not.
active_layout() {
    osascript <<EOF 2>/dev/null
tell application "System Events"
  tell process "$PROCESS_NAME"
    repeat with i in menu items of menu 1 of menu item "Layout" of menu 1 of menu bar item "Data Fields" of menu bar 1
      try
        if (value of attribute "AXMenuItemMarkChar" of i) is not missing value then
          return name of i
        end if
      end try
    end repeat
    return ""
  end tell
end tell
EOF
}

# Block until the simulator reports `layout_name` as active.
wait_for_active_layout() {
    local layout_name=$1
    local waited=0
    while [ "$(active_layout)" != "$layout_name" ]; do
        sleep "$poll_seconds"
        waited=$(awk -v a="$waited" -v b="$poll_seconds" 'BEGIN{print a+b}')
        if awk -v w="$waited" -v t="$timeout_seconds" 'BEGIN{exit !(w>=t)}'; then
            return 1
        fi
    done
    return 0
}

# Capture into `out`, retrying until the image differs from `previous_hash` and
# has stopped changing. Returns 0 on a verified-new frame, 1 on timeout.
#
# This is the part that actually fixes the off-by-one: without it the script
# happily saves the last layout's pixels under the new layout's filename.
capture_when_redrawn() {
    local out=$1
    local previous_hash=$2
    local region=$3
    local waited=0
    local last_hash=""
    local this_hash=""

    while :; do
        screencapture -x -R"$region" "$out"
        this_hash="$(md5 -q "$out")"

        # New frame AND stable across two polls — a partially painted window can
        # differ from the previous layout while still not being finished.
        if [ "$this_hash" != "$previous_hash" ] && [ "$this_hash" = "$last_hash" ]; then
            return 0
        fi
        last_hash="$this_hash"

        sleep "$poll_seconds"
        waited=$(awk -v a="$waited" -v b="$poll_seconds" 'BEGIN{print a+b}')
        if awk -v w="$waited" -v t="$timeout_seconds" 'BEGIN{exit !(w>=t)}'; then
            return 1
        fi
    done
}

# "3 Fields A" -> "03-fields-a", so the directory sorts the way the menu reads.
slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/^\([0-9]\) /0\1-/' -e 's/^\([0-9][0-9]\) /\1-/' -e 's/ /-/g'
}

# ── Capture ──────────────────────────────────────────────────────────────────

if [ "$dry_run" -eq 1 ]; then
    print_colored "$COLOR_YELLOW" "Layouts that would be captured:"
fi

captured=0
skipped=0
unverified=0

# Seed the comparison with what is on screen BEFORE any layout change.
#
# Without this the first capture has nothing to be compared against, so a stale
# frame sails through — which is exactly how a run that starts on "10 Fields"
# ends up writing the 10-field rendering into 01-field.png.
seed_capture="$(mktemp -t ciqseed).png"
trap 'rm -f "$seed_capture"' EXIT
previous_hash=""
if [ "$dry_run" -eq 0 ]; then
    seed_region="$(window_region)"
    if [ -n "$seed_region" ]; then
        screencapture -x -R"$seed_region" "$seed_capture"
        previous_hash="$(md5 -q "$seed_capture")"
    fi
fi

while IFS= read -r layout; do
    [ -z "$layout" ] && continue
    if [ -n "$only_pattern" ]; then
        # shellcheck disable=SC2254  # glob match is intentional
        case "$layout" in
            $only_pattern) ;;
            *) skipped=$((skipped + 1)); continue ;;
        esac
    fi

    if [ "$dry_run" -eq 1 ]; then
        printf '  %s -> %s.png\n' "$layout" "$(slugify "$layout")"
        captured=$((captured + 1))
        continue
    fi

    mkdir -p "$output_dir"

    # Already showing this layout? Then no redraw is coming and waiting for one
    # would time out. The screen is correct as it stands, so capture it.
    already_active=0
    if [ "$(active_layout)" = "$layout" ]; then
        already_active=1
    fi

    select_layout "$layout"

    if ! wait_for_active_layout "$layout"; then
        print_colored "$COLOR_RED" "  $layout: simulator never reported it active, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    region="$(window_region)"
    if [ -z "$region" ]; then
        print_colored "$COLOR_RED" "  $layout: could not locate the simulator window, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    out="$output_dir/$(slugify "$layout").png"
    if [ "$already_active" -eq 1 ]; then
        sleep "$poll_seconds"
        screencapture -x -R"$region" "$out"
        printf "  %-12s ${COLOR_BRIGHTYELLOW}%s${COLOR_RESET}  (already active)\n" "$layout" "$out"
    elif capture_when_redrawn "$out" "$previous_hash" "$region"; then
        printf "  %-12s ${COLOR_BRIGHTYELLOW}%s${COLOR_RESET}\n" "$layout" "$out"
    else
        # Either the redraw never came, or this layout genuinely renders
        # identically to the last one — which can happen when the field is
        # the same size in both. Say so rather than silently saving.
        printf "  %-12s ${COLOR_RED}%s  (unchanged from previous — verify)${COLOR_RESET}\n" "$layout" "$out"
        unverified=$((unverified + 1))
    fi
    previous_hash="$(md5 -q "$out")"
    captured=$((captured + 1))
done <<< "$layout_list"

echo ""
if [ "$dry_run" -eq 1 ]; then
    print_colored "$COLOR_GREEN" "$captured layout(s) would be captured. Re-run without --dry-run."
else
    print_colored "$COLOR_GREEN" "Captured $captured layout(s) to $output_dir"
    [ "$skipped" -gt 0 ] && print_colored "$COLOR_YELLOW" "Skipped $skipped."
    if [ "$unverified" -gt 0 ]; then
        print_colored "$COLOR_RED" "$unverified capture(s) could not be verified as a fresh redraw."
        print_colored "$COLOR_YELLOW" "  Either raise --timeout, or those layouts render identically here."
    fi

    # Identical files mean two layouts produced the same pixels — usually a
    # missed redraw, occasionally two layouts that really do look the same.
    dupes="$(md5 -q "$output_dir"/*.png 2>/dev/null | sort | uniq -d | wc -l | tr -d " ")"
    if [ "${dupes:-0}" -gt 0 ]; then
        print_colored "$COLOR_RED" "$dupes duplicate image(s) detected — inspect before trusting these."
    else
        print_colored "$COLOR_GREEN" "All captures are distinct."
    fi
    print_colored "$COLOR_YELLOW" "  open $output_dir"
fi
