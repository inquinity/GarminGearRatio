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
settle_seconds=0.7
dry_run=0
only_pattern=""

usage() {
    cat <<'USAGE'
Usage: tools/capture-layouts.sh [options]

Steps the running CIQ simulator through every data-field layout and saves a
PNG of the simulator window for each one.

Options:
  -o, --output DIR   Directory for PNGs (default: captures/<timestamp>)
  -m, --match GLOB   Only layouts whose name matches, e.g. '1 Field' or '*B'
  -s, --settle SECS  Pause after each layout change before capturing (default 0.7)
  -n, --dry-run      List the layouts that would be captured, change nothing
  -h, --help         Show this help

Examples:
  tools/capture-layouts.sh
  tools/capture-layouts.sh --match '1 Field' --output /tmp/one
  tools/capture-layouts.sh --dry-run
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)  output_dir="$2"; shift 2 ;;
        -m|--match)   only_pattern="$2"; shift 2 ;;
        -s|--settle)  settle_seconds="$2"; shift 2 ;;
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
    select_layout "$layout"
    sleep "$settle_seconds"

    region="$(window_region)"
    if [ -z "$region" ]; then
        print_colored "$COLOR_RED" "  $layout: could not locate the simulator window, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    out="$output_dir/$(slugify "$layout").png"
    screencapture -x -R"$region" "$out"
    printf "  %-12s ${COLOR_BRIGHTYELLOW}%s${COLOR_RESET}\n" "$layout" "$out"
    captured=$((captured + 1))
done <<< "$layout_list"

echo ""
if [ "$dry_run" -eq 1 ]; then
    print_colored "$COLOR_GREEN" "$captured layout(s) would be captured. Re-run without --dry-run."
else
    print_colored "$COLOR_GREEN" "Captured $captured layout(s) to $output_dir"
    [ "$skipped" -gt 0 ] && print_colored "$COLOR_YELLOW" "Skipped $skipped."
    print_colored "$COLOR_YELLOW" "  open $output_dir"
fi
