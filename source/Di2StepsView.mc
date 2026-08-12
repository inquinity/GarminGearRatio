import Toybox.Activity;
import Toybox.Application.Properties;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
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

    // Last rear position actually drawn, so logShift fires on change only.
    private var _loggedRearPos as Number? = null;

    // Ride screen tuning. The stacked-vs-side-by-side decision itself lives in
    // GearConfig.ridePrefersSideBySide, where it is tested against every real
    // slot size on the device.
    //
    // Smallest TEXT_FONTS index the ratio may shrink to before the tooth pair is
    // dropped and the whole slot given to the number. Index 2 = FONT_SMALL. This
    // is what protects 239x158 — the tightest slot and by far the most common.
    private const RIDE_MIN_FONT = 2;

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

    // Rider-facing screen: the gear ratio, as large as the slot allows, with the
    // tooth pair alongside when there is room to spare.
    //
    // The ratio is never sacrificed. Teeth are the expendable element: they
    // exist to confirm the position→teeth mapping is right, which is the one
    // thing that can only be checked on a ride. If showing them would shrink
    // the ratio below RIDE_MIN_FONT, they are dropped and the whole slot goes
    // to the number.
    private function drawRide(dc as Graphics.Dc) as Void {
        var frontPos = _data.frontPosition(_config);
        var rearPos  = _data.rearPosition();

        var ratio = ratioText(frontPos, rearPos);
        var teeth = teethPairText(frontPos, rearPos);

        var margin = 4;
        var x = margin;
        var y = margin;
        var w = dc.getWidth()  - 2 * margin;
        var h = dc.getHeight() - 2 * margin;

        if (teeth == null) {
            drawFitted(dc, ratio, x, y, w, h, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Split the box and fit each part on its own, rather than laying out one
        // combined string — a single string forces both values to share a font,
        // and the ratio would shrink to accommodate the annotation. Separation
        // is whitespace, not a punctuation glyph.
        //
        // Wide strips split vertically (side by side); everything else splits
        // horizontally (stacked), where a line break is the natural separator.
        if ($.ridePrefersSideBySide(w, h)) {
            var gutter    = w / 16;
            var ratioW    = (w - gutter) * 62 / 100;
            var teethW    = w - gutter - ratioW;
            var ratioFont = fitFont(dc, [ratio], ratioW, h);
            if (fontIndex(ratioFont) < RIDE_MIN_FONT) {
                drawFitted(dc, ratio, x, y, w, h, Graphics.TEXT_JUSTIFY_CENTER);
                return;
            }
            // Shared baseline so the two values don't look ragged.
            var teethFont = fitFont(dc, [teeth], teethW, h / 2);
            var lh        = dc.getFontHeight(ratioFont);
            var baseY     = y + (h - lh) / 2;
            dc.drawText(x + ratioW, baseY, ratioFont, ratio, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(x + ratioW + gutter,
                        baseY + lh - dc.getFontHeight(teethFont),
                        teethFont, teeth, Graphics.TEXT_JUSTIFY_LEFT);
            return;
        }

        // Stacked: give the teeth a fixed slice off the bottom, ratio takes the
        // rest. If that leaves the ratio too small, drop the teeth entirely.
        var teethH    = h / 4;
        var ratioH    = h - teethH;
        var stackFont = fitFont(dc, [ratio], w, ratioH);
        if (fontIndex(stackFont) < RIDE_MIN_FONT) {
            drawFitted(dc, ratio, x, y, w, h, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        drawFitted(dc, ratio, x, y, w, ratioH, Graphics.TEXT_JUSTIFY_CENTER);
        drawFitted(dc, teeth, x, y + ratioH, w, teethH, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // "47:17", or null when either end is unknown — in which case there is
    // nothing meaningful to annotate the ratio with.
    private function teethPairText(frontPos as Number?, rearPos as Number?) as String? {
        var tf = _config.frontTeethAt(frontPos);
        var tr = _config.rearTeethAt(rearPos);
        if (tf == null || tr == null) {
            return null;
        }
        return tf.toString() + ":" + tr.toString();
    }

    // Draw one string at the largest font fitting the box, vertically centred.
    private function drawFitted(dc as Graphics.Dc, text as String, x as Number, y as Number,
                                w as Number, h as Number, justify as Number) as Void {
        var font = fitFont(dc, [text], w, h);
        var tx = (justify == Graphics.TEXT_JUSTIFY_CENTER) ? x + w / 2 : x;
        dc.drawText(tx, y + (h - dc.getFontHeight(font)) / 2, font, text, justify);
    }

    // Position of a font within TEXT_FONTS, for comparing against a floor.
    private function fontIndex(font as Graphics.FontDefinition) as Number {
        for (var i = 0; i < TEXT_FONTS.size(); i++) {
            if (TEXT_FONTS[i] == font) {
                return i;
            }
        }
        return 0;
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
        lines.add("Front Position = " + posOr(frontPos));
        lines.add("Front Teeth = " + numOr(_config.frontTeethAt(frontPos)));
        lines.add("Rear Position = " + posOr(rearPos));
        lines.add("Rear Teeth = " + numOr(_config.rearTeethAt(rearPos)));
        var ratio = ratioText(frontPos, rearPos);
        lines.add("Ratio = " + ratio);
        logShift(rearPos, _config.rearTeethAt(rearPos), ratio);
        drawBlock(dc, lines, 4, 4, dc.getWidth() - 8, dc.getHeight() - 8);
    }

    // One line per rendered gear change, for investigating shift-to-screen
    // latency after a ride. Fires only when the drawn position actually changes
    // — a few times a minute, not every frame — so it costs nothing in normal
    // riding.
    //
    // `render` is the gap between sampling first seeing this position and this
    // draw putting it on screen. It is the only part of the delay this app
    // controls; the head unit's own reporting delay is invisible to us.
    //
    // Position, teeth and ratio are logged together deliberately. All three come
    // from one sample in one draw, so they cannot disagree — and a log showing
    // them disagree would disprove that, which is the open question from the
    // 2026-08-10 ride.
    private function logShift(rearPos as Number?, teeth as Number?, ratio as String) as Void {
        if (rearPos == _loggedRearPos) {
            return;
        }
        _loggedRearPos = rearPos;

        var now = System.getTimer();
        var render = (_data.rearChangedAtMs > 0) ? (now - _data.rearChangedAtMs) : -1;
        System.println("di2steps t=" + now
            + " rear=" + ((rearPos == null) ? "--" : rearPos.toString())
            + " teeth=" + ((teeth == null) ? "--" : teeth.toString())
            + " ratio=" + ratio
            + " render=" + render + "ms");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // "--" covers both "not sampled yet" and "sampled, head unit had nothing".
    // These were rendered separately ("--" vs "null") during the 2026-08-09
    // probe, when telling them apart was the entire point; that question is
    // settled, so the screen now reads consistently instead. Restoring the
    // distinction is a two-line change if a future symptom needs it.
    //
    // "n/a" is deliberately NOT folded in — it means the API doesn't expose
    // derailleur fields on this device at all, which is a different problem
    // from having no data right now.
    private function posOr(n as Number?) as String {
        if (!_data.supported) {
            return "n/a";
        }
        return (n == null) ? "--" : n.toString();
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
