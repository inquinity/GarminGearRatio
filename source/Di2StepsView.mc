import Toybox.Activity;
import Toybox.Application.Properties;
import Toybox.BluetoothLowEnergy;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.WatchUi;

using Toybox.BluetoothLowEnergy as Ble;

// Display modes, selected by the DisplayMode app-setting property.
// The field owns one BLE connection and renders one of these modes; there is
// no in-activity button navigation, so "pages" are chosen in settings.
enum {
    MODE_RIDE        = 0,  // gear / ratio / assist mode — replaces a Di2 page
    MODE_GEAR_CONFIG = 1,  // drivetrain topology + tooth counts
    MODE_TEST        = 2   // name/value table of every decoded field
}

class Di2StepsView extends WatchUi.DataField {

    private var _mode as Number = MODE_TEST;
    private var _data as StepsData;
    private var _ble as ShimanoBleDelegate?;

    // Read battery only every N seconds once we have a value (emtb pattern).
    private const BATTERY_INTERVAL = 15;
    private var _secsSinceBattery as Number = BATTERY_INTERVAL;

    // Shown on the Test screen so you can tell at a glance which build the Edge
    // is actually running. Bump this alongside the manifest version on every
    // push — a stale tag is worse than no tag.
    private const BUILD_TAG = "B5";

    private const ASSIST_NAMES = ["Off", "Eco", "Trail", "Boost", "Walk"];
    private const RAW_TAGS = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06];

    // Font ladders, smallest → largest. A data field's dc is sized to its slot
    // (full-screen single field, half-width, or one row of a multi-field page),
    // so we pick the largest font whose content still fits rather than hardcode.
    private const TEXT_FONTS = [
        Graphics.FONT_XTINY,
        Graphics.FONT_TINY,
        Graphics.FONT_SMALL,
        Graphics.FONT_MEDIUM,
        Graphics.FONT_LARGE
    ];

    function initialize() {
        DataField.initialize();
        _data = new StepsData();
        loadSettings();
    }

    // Called by the app right after construction to bring up BLE. Kept separate
    // from initialize() to mirror emtb's proven setup timing.
    function setupBle() as Void {
        _ble = new ShimanoBleDelegate(_data);
        Ble.setDelegate(_ble);
        pushLockSettings();
    }

    // ── Settings ──────────────────────────────────────────────────────────────

    function loadSettings() as Void {
        var m = Properties.getValue("DisplayMode");
        _mode = (m instanceof Number) ? m : MODE_TEST;
    }

    function onSettingsChanged() as Void {
        loadSettings();
        pushLockSettings();
        WatchUi.requestUpdate();
    }

    // Parse the LastMAC hex string and hand the lock config to the delegate.
    private function pushLockSettings() as Void {
        if (_ble == null) {
            return;
        }
        var lock = Properties.getValue("LastLock");
        lock = (lock instanceof Boolean) ? lock : false;

        var macArray = null;
        var macStr = Properties.getValue("LastMAC");
        if (macStr instanceof String && macStr.length() > 0) {
            try {
                macArray = StringUtil.convertEncodedString(macStr, {
                    :fromRepresentation => StringUtil.REPRESENTATION_STRING_HEX,
                    :toRepresentation   => StringUtil.REPRESENTATION_BYTE_ARRAY
                });
            } catch (e) {
                macArray = null;
            }
        }
        _ble.setLock(lock, macArray);
    }

    // ── Per-second update ─────────────────────────────────────────────────────

    function compute(info as Activity.Info) as Void {
        // Second data source, independent of BLE: the head unit decodes STEPS
        // gear position itself. Sampled before the BLE early-return below so it
        // still populates if the BLE stack never comes up.
        _data.onActivityInfo(info);

        if (_ble == null) {
            return;
        }
        _secsSinceBattery += 1;
        if (_data.battery < 0 || _secsSinceBattery >= BATTERY_INTERVAL) {
            _secsSinceBattery = 0;
            _ble.requestReadBattery();
        }
        _ble.requestNotifyMode(true);
        _ble.compute();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);
        dc.clear();
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);

        if (_mode == MODE_RIDE) {
            drawRide(dc);
        } else if (_mode == MODE_GEAR_CONFIG) {
            drawGearConfig(dc);
        } else {
            drawTest(dc);
        }
    }

    // ── Render modes ──────────────────────────────────────────────────────────

    // Stage 3 fills this in (gear / ratio / assist mode).
    private function drawRide(dc as Graphics.Dc) as Void {
        drawCentered(dc, "Di2 STEPS\nRide");
    }

    // Stage 4 fills this in (drivetrain topology + tooth counts).
    private function drawGearConfig(dc as Graphics.Dc) as Void {
        drawCentered(dc, "Di2 STEPS\nGear Config");
    }

    // Diagnostics: connection status, every decoded field, and the last raw
    // packet seen per type-tag. This is the primary check that data retrieval
    // works end-to-end.
    private function drawTest(dc as Graphics.Dc) as Void {
        // Decoded values: short labels so line WIDTH doesn't force a tiny font.
        // These are what you watch while testing, so they get the large block.
        var values = [];
        // Build tag + live field size. Confirms which build is actually running
        // on device (the Edge keeps the old app if the manifest version didn't
        // increase) and what dc size onUpdate is handed. Re-tag on every push.
        values.add(BUILD_TAG + " " + dc.getWidth() + "x" + dc.getHeight());
        values.add(statusLine());
        // Rows prefixed "A:" come from Activity.Info, not from the BLE stream.
        // Shown adjacent to the BLE gear row on purpose: this side-by-side is
        // the comparison the whole probe exists to make.
        values.add("Gear " + numOr(_data.gear) + "/" + numOr(_data.maxGear));
        values.add("A:R " + actOr(_data.rearIndex) + "/" + actOr(_data.rearMax)
                   + " t" + actOr(_data.rearSize));
        values.add("A:F " + actOr(_data.frontIndex) + "/" + actOr(_data.frontMax)
                   + " t" + actOr(_data.frontSize));
        values.add("Mode " + modeLabel());
        values.add("Speed " + (_data.speed >= 0 ? _data.speed.format("%.1f") : "--"));
        values.add("Cad " + numOr(_data.cadence));
        values.add("Asst " + numOr(_data.assistLevel));
        values.add("Bat " + (_data.battery >= 0 ? _data.battery.toString() + "%" : "--"));
        if (_data.profileName != null) {
            values.add("Prof " + _data.profileName);
        }
        // Raw per-tag hex capture: inherently wide, so keep it in its own small
        // block at the bottom instead of shrinking every value line to match.
        var raw = [];
        for (var i = 0; i < RAW_TAGS.size(); i++) {
            var tag = RAW_TAGS[i];
            var hex = _data.hexFor(tag);
            if (!hex.equals("")) {
                raw.add(tag.format("%02X") + ": " + clip(hex, 34));
            }
        }
        drawTestLayout(dc, values, raw);
    }

    // Values fill the slot at the largest font that fits; raw hex (if any) gets
    // a small fixed-font strip at the bottom, capped so it can't starve values.
    private function drawTestLayout(dc as Graphics.Dc, values as Array, raw as Array) as Void {
        var margin = 4;
        var x = margin;
        var top = margin;
        var w = dc.getWidth() - 2 * margin;
        var totalH = dc.getHeight() - 2 * margin;

        if (raw.size() == 0) {
            drawBlock(dc, values, x, top, w, totalH);
            return;
        }

        var rawFont = Graphics.FONT_XTINY;
        var rawLh = dc.getFontHeight(rawFont);
        var rawH = rawLh * raw.size();
        var maxRawH = totalH * 2 / 5;   // raw never takes more than 40% of height
        if (rawH > maxRawH) {
            rawH = maxRawH;
        }
        drawBlock(dc, values, x, top, w, totalH - rawH);

        var ry = top + (totalH - rawH);
        for (var i = 0; i < raw.size(); i++) {
            if (ry + rawLh > top + totalH) {
                break;
            }
            dc.drawText(x, ry, rawFont, raw[i], Graphics.TEXT_JUSTIFY_LEFT);
            ry += rawLh;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private function statusLine() as String {
        if (_ble == null) {
            return "Bluetooth off";
        } else if (_ble.isConnecting()) {
            return _ble.isRegistered() ? "Scanning..." : "Initializing...";
        } else if (_ble.isConnected()) {
            return "Connected";
        }
        return "Disconnected";
    }

    private function modeLabel() as String {
        if (_data.assistMode < 0) {
            return "--";
        }
        var name = (_data.assistMode < ASSIST_NAMES.size()) ? ASSIST_NAMES[_data.assistMode] : "?";
        return _data.assistMode.toString() + " " + name;
    }

    private function numOr(n as Number) as String {
        return (n >= 0) ? n.toString() : "--";
    }

    // Activity.Info fields are nullable, so they need three renderings, not two.
    // "null" must stay visually distinct from "--": "--" means we haven't looked
    // yet, "null" means we looked and the head unit had nothing — which is the
    // expected result for the teeth fields and the answer this probe is after.
    private function actOr(n as Number?) as String {
        if (!_data.activitySupported) {
            return "n/a";
        } else if (!_data.activityRead) {
            return "--";
        } else if (n == null) {
            return "null";
        }
        return n.toString();
    }

    private function clip(s as String, max as Number) as String {
        return (s.length() > max) ? s.substring(0, max) : s;
    }

    // Largest font from TEXT_FONTS whose line height (× lineCount) and widest
    // line both fit within the given box. Falls back to the smallest font.
    private function fitFont(dc as Graphics.Dc, lines as Array, w as Number, h as Number) as Graphics.FontDefinition {
        var best = TEXT_FONTS[0];
        for (var f = 0; f < TEXT_FONTS.size(); f++) {
            var font = TEXT_FONTS[f];
            if (dc.getFontHeight(font) * lines.size() > h) {
                break;
            }
            var widest = 0;
            for (var i = 0; i < lines.size(); i++) {
                var tw = dc.getTextWidthInPixels(lines[i], font);
                if (tw > widest) {
                    widest = tw;
                }
            }
            if (widest > w) {
                break;
            }
            best = font;
        }
        return best;
    }

    // Left-aligned lines filling the given box at the largest font that fits,
    // vertically centered within the box.
    private function drawBlock(dc as Graphics.Dc, lines as Array, x as Number, y as Number, w as Number, h as Number) as Void {
        var font = fitFont(dc, lines, w, h);
        var lh = dc.getFontHeight(font);
        var ty = y + (h - lh * lines.size()) / 2;
        if (ty < y) {
            ty = y;
        }
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(x, ty, font, lines[i], Graphics.TEXT_JUSTIFY_LEFT);
            ty += lh;
        }
    }

    private function drawCentered(dc as Graphics.Dc, msg as String) as Void {
        var lines = split(msg, "\n");
        var margin = 4;
        var w = dc.getWidth() - 2 * margin;
        var h = dc.getHeight() - 2 * margin;
        var font = fitFont(dc, lines, w, h);
        var lh = dc.getFontHeight(font);
        var cx = dc.getWidth() / 2;
        var y = (dc.getHeight() - lh * lines.size()) / 2;
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, y, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += lh;
        }
    }

    // Minimal string splitter (Monkey C has no String.split for arbitrary seps).
    private function split(s as String, sep as String) as Array<String> {
        var out = [];
        var idx = s.find(sep);
        while (idx != null) {
            out.add(s.substring(0, idx));
            s = s.substring(idx + sep.length(), s.length());
            idx = s.find(sep);
        }
        out.add(s);
        return out;
    }
}
