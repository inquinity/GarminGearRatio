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

    private const ASSIST_NAMES = ["Off", "Eco", "Trail", "Boost", "Walk"];
    private const RAW_TAGS = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06];

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
        var lines = [];
        lines.add(statusLine());
        lines.add("Gear: " + numOr(_data.gear) + " / " + numOr(_data.maxGear));
        lines.add("Assist Mode: " + modeLabel());
        lines.add("Speed: " + (_data.speed >= 0 ? _data.speed.format("%.1f") : "--"));
        lines.add("Cadence: " + numOr(_data.cadence));
        lines.add("Assist Level: " + numOr(_data.assistLevel));
        lines.add("Battery: " + (_data.battery >= 0 ? _data.battery.toString() + "%" : "--"));
        if (_data.profileName != null) {
            lines.add("Profile: " + _data.profileName);
        }
        for (var i = 0; i < RAW_TAGS.size(); i++) {
            var tag = RAW_TAGS[i];
            var hex = _data.hexFor(tag);
            if (!hex.equals("")) {
                lines.add("Type " + tag.format("%02X") + ": " + clip(hex, 34));
            }
        }
        drawList(dc, lines);
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

    private function clip(s as String, max as Number) as String {
        return (s.length() > max) ? s.substring(0, max) : s;
    }

    private function drawList(dc as Graphics.Dc, lines as Array) as Void {
        var font = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(font);
        var x = 6;
        var y = 4;
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(x, y, font, lines[i], Graphics.TEXT_JUSTIFY_LEFT);
            y += lh;
        }
    }

    private function drawCentered(dc as Graphics.Dc, msg as String) as Void {
        dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_SMALL, msg,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
