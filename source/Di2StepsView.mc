import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The field renders one screen: the ratio. There used to be a DisplayMode
// setting choosing between Ride, Gear Config and Test, but a rider cannot tell
// which mode a field is in by looking at it, and the setting was a state toggle
// with no visible state — removed 2026-08-19.
//
// drawTest is kept below as a diagnostic. Flip this to true and rebuild to get
// the name/value table back; there is deliberately no way to reach it at
// runtime.
const SHOW_DIAGNOSTICS = false;

class Di2StepsView extends WatchUi.DataField {

    private var _data as StepsData;
    private var _config as GearConfig;

    // Last rear position actually drawn, so logShift fires on change only.
    private var _loggedRearPos as Number? = null;

    // Shown above the ratio. Connect IQ draws no label for a data field, so
    // without this ours is the only unidentified number on a crowded screen.
    private const RIDE_LABEL = "RATIO";

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
    }

    // ── Settings ──────────────────────────────────────────────────────────────

    function onSettingsChanged() as Void {
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

        // Logged here, not inside a draw mode: shift timing is a property of the
        // data and this frame, not of which screen happens to be selected. It
        // previously lived in drawTest, which meant riding in Ride mode — the
        // normal case — produced no timing data at all.
        logShift();

        var bg = getBackgroundColor();
        var fg = (bg == Graphics.COLOR_BLACK) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(fg, bg);
        dc.clear();
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);

        if ($.SHOW_DIAGNOSTICS) {
            drawTest(dc);
        } else {
            drawRide(dc);
        }
    }

    // ── Render modes ──────────────────────────────────────────────────────────

    // Rider-facing screen: label, ratio, and the tooth pair as ONE centred
    // group. Geometry comes from computeRideLayout (RideLayout.mc), which is
    // probed against every real slot size on the device.
    private function drawRide(dc as Graphics.Dc) as Void {
        var frontPos = _data.frontPosition(_config);
        var rearPos  = _data.rearPosition();
        drawRideBlock(dc, ratioText(frontPos, rearPos), teethPairText(frontPos, rearPos));
    }

    // Split from drawRide so a preview build can feed it fixed sample values —
    // the simulator has no drivetrain, so live data renders as "--" and shows
    // nothing about the layout.
    private function drawRideBlock(dc as Graphics.Dc, ratio as String, teeth as String?) as Void {
        // Full slot dimensions, no margin: the parity geometry is expressed in
        // the device's own slot coordinates, so insetting would shift everything
        // off the native baselines.
        var w  = dc.getWidth();
        var h  = dc.getHeight();
        var cx = w / 2;

        var layout = $.computeRideLayout(dc, w, h, RIDE_LABEL, ratio, teeth);

        if (layout.showLabel) {
            dc.drawText(cx, layout.labelY, layout.labelFont, RIDE_LABEL,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.drawText(cx, layout.valueY, layout.valueFont, ratio,
                    Graphics.TEXT_JUSTIFY_CENTER);
        if (layout.showTeeth && teeth != null) {
            dc.drawText(cx, layout.teethY, layout.teethFont, teeth,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
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
        lines.add("Ratio = " + ratioText(frontPos, rearPos));
        drawBlock(dc, lines, 4, 4, dc.getWidth() - 8, dc.getHeight() - 8);
    }

    // One line per gear change, for investigating shift-to-screen latency after
    // a ride. Fires only when the position actually changes — a few times a
    // minute, not every frame — so it costs nothing in normal riding.
    //
    // Called from onUpdate, so it runs in EVERY display mode. It used to be
    // called from drawTest, which meant a ride in Ride mode logged nothing.
    //
    // `render` is the gap between sampling first seeing this position and the
    // frame that puts it on screen. It is the only part of the delay this app
    // controls; the head unit's own reporting delay is invisible to us.
    //
    // Position, teeth and ratio are logged together deliberately. All three come
    // from one sample in one frame, so they cannot disagree — and a log showing
    // them disagree would disprove that, which is the open question from the
    // 2026-08-10 ride.
    private function logShift() as Void {
        var rearPos = _data.rearPosition();
        if (rearPos == _loggedRearPos) {
            return;
        }
        _loggedRearPos = rearPos;

        var teeth = _config.rearTeethAt(rearPos);
        var ratio = ratioText(_data.frontPosition(_config), rearPos);
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

}
