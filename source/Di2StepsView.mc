import Toybox.Activity;
import Toybox.Application.Properties;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Display modes, selected by the DisplayMode app-setting property.
// There is no in-activity button navigation, so "pages" are chosen in settings.
enum {
    MODE_RIDE        = 0,  // gear / ratio — the rider-facing screen
    MODE_GEAR_CONFIG = 1,  // drivetrain topology + tooth counts
    MODE_TEST        = 2   // name/value table of every field, for diagnostics
}

class Di2StepsView extends WatchUi.DataField {

    private var _mode as Number = MODE_TEST;
    private var _data as StepsData;
    private var _config as GearConfig;

    // Shown on the Test screen so you can tell at a glance which build the Edge
    // is actually running. Bump this alongside the manifest version on every
    // push — a stale tag is worse than no tag.
    private const BUILD_TAG = "B6";

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
        _config = new GearConfig();
        loadSettings();
    }

    // ── Settings ──────────────────────────────────────────────────────────────

    function loadSettings() as Void {
        var m = Properties.getValue("DisplayMode");
        _mode = (m instanceof Number) ? m : MODE_TEST;
    }

    function onSettingsChanged() as Void {
        loadSettings();
        _config.load();
        WatchUi.requestUpdate();
    }

    // ── Per-second update ─────────────────────────────────────────────────────

    function compute(info as Activity.Info) as Void {
        _data.onActivityInfo(info);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        // Re-sample at draw time rather than relying solely on the value cached
        // by compute(). compute() runs at 1 Hz and onUpdate can run before it in
        // a cycle, which rendered the previous second's gear — the ~1s lag
        // behind Garmin's built-in field observed on 2026-08-09.
        var info = Activity.getActivityInfo();
        if (info != null) {
            _data.onActivityInfo(info);
        }

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

    // Rider-facing screen: to be built once the Test screen confirms the
    // numbers are right.
    private function drawRide(dc as Graphics.Dc) as Void {
        drawCentered(dc, "Di2 STEPS\nRide");
    }

    // Drivetrain topology + tooth counts.
    private function drawGearConfig(dc as Graphics.Dc) as Void {
        drawCentered(dc, "Di2 STEPS\nGear Config");
    }

    // Diagnostics: position and teeth for each end of the drivetrain, plus the
    // resulting ratio. Positions come live from Activity.Info; teeth come from
    // settings, because the head unit's teeth values are unusable on this bike.
    private function drawTest(dc as Graphics.Dc) as Void {
        var frontPos = _data.frontPosition(_config);
        var rearPos  = _data.rearPosition();

        var lines = [];
        lines.add(BUILD_TAG + " " + dc.getWidth() + "x" + dc.getHeight());
        lines.add("Front: Position = " + posOr(frontPos) + " Teeth = " + numOr(_config.frontTeethAt(frontPos)));
        lines.add("Rear: Position = " + posOr(rearPos) + " Teeth = " + numOr(_config.rearTeethAt(rearPos)));
        lines.add("Ratio = " + ratioText(frontPos, rearPos));
        drawBlock(dc, lines, 4, 4, dc.getWidth() - 8, dc.getHeight() - 8);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Gear positions come from Activity.Info, so they need three renderings.
    // "--" (never sampled) must stay distinct from "null" (sampled, head unit
    // had nothing) — conflating them hid a whole ride's worth of diagnosis.
    private function posOr(n as Number?) as String {
        if (!_data.supported) {
            return "n/a";
        } else if (!_data.read) {
            return "--";
        } else if (n == null) {
            return "null";
        }
        return n.toString();
    }

    // Teeth come from settings, so there are only two cases: configured, or not.
    private function numOr(n as Number?) as String {
        return (n == null) ? "--" : n.toString();
    }

    // Two decimal places, e.g. "1.00", "2.67", "4.60". "--" when either end is
    // unconfigured — better than a fabricated 0.00 that looks like a reading.
    private function ratioText(frontPos as Number?, rearPos as Number?) as String {
        var r = _config.ratio(frontPos, rearPos);
        return (r == null) ? "--" : r.format("%.2f");
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
