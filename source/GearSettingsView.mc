import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Shown when the rider opens this data field's settings on the device.
//
// This IS the configuration overview: the drivetrain as configured, in the
// terms it was entered in — how many sprockets at each end, and which ones.
// OK starts the wizard, Back exits.
//
// Ported from ../GarminGearRatioVersion1/source/GearSettingsView.mc. Adapted: that app
// derives its topology from a "Di2 profile" property, which this app does not
// have — front ring count is a setting and rear cog count is known live from
// Activity.Info, so the wizard asks for both instead.
class GearSettingsView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        var config = new GearConfig();
        var configured = config.frontTeeth.size() > 0 && config.rearTeeth.size() > 0;

        // No title drawn: the system puts the app's name in the settings header
        // bar directly above this view.
        var lines = [];
        lines.add("Front gears: " + count(config.frontTeeth));
        lines.addAll($.teethListLines(config.frontTeeth));
        lines.add("Rear gears: " + count(config.rearTeeth));
        lines.addAll($.teethListLines(config.rearTeeth));

        // Vertically centred as a block, so a 1x11 (five lines) and a 2x12 (six)
        // both sit sensibly rather than one drifting off the bottom.
        var lh = dc.getFontHeight(Graphics.FONT_SMALL);
        var y  = (h - lh * lines.size()) / 2 - lh / 2;
        if (y < lh / 2) {
            y = lh / 2;
        }
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(w / 2, y + lh * i, Graphics.FONT_SMALL, lines[i],
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        var hint = configured ? "Press OK to change" : "Press OK to set up";
        dc.drawText(w / 2, h * 88 / 100, Graphics.FONT_TINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function count(teeth as Array<Number>) as String {
        return (teeth.size() == 0) ? "not set" : teeth.size().toString();
    }
}

// The sprockets themselves, wrapped over as many lines as they need — an
// 11-speed cassette does not fit on one line at a legible size, and there is
// room here for two or three.
//
// Always rendered SMALLEST..LARGEST, which is how drivetrains are described
// everywhere ("11-50 cassette"), regardless of how the teeth are stored.
// Internally the rear is held largest-first because position 1 is the easiest
// gear — that ordering is load-bearing for the ratio lookup and must not be
// "fixed" to match this display.
const TEETH_PER_LINE = 6;

function teethListLines(teeth as Array<Number>) as Array<String> {
    if (teeth.size() == 0) {
        return [] as Array<String>;
    }
    var ordered = $.sortAscending(teeth);
    var out = [] as Array<String>;
    var line = "";
    for (var i = 0; i < ordered.size(); i++) {
        line = line.equals("") ? ordered[i].toString() : line + "  " + ordered[i].toString();
        if ((i + 1) % $.TEETH_PER_LINE == 0) {
            out.add(line);
            line = "";
        }
    }
    if (!line.equals("")) {
        out.add(line);
    }
    return out;
}
