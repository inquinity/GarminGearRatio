import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Shown when the rider opens this data field's settings on the device.
//
// This IS the configuration overview: everything the field knows about the
// drivetrain on one screen — what was entered, what the head unit detected, and
// the ratio range those produce. OK starts the wizard, Back exits.
//
// The ratio range is the most useful line and the reason the screen exists. It
// is derived, so a transposed or truncated cassette shows up as a nonsense
// spread here rather than as a wrong number mid-ride.
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

        var lines = [
            "Front: " + summarise(config.frontTeeth),
            "Rear: "  + summarise(config.rearTeeth),
            "Ratio: " + $.ratioRangeText(config),
            "Bike: "  + detected()
        ];
        var hint = configured ? "Press OK to change" : "Press OK to set up";

        // No title drawn: the system puts the app's name in the settings header
        // bar directly above this view, so drawing "Gear Ratio" again just
        // repeated it and cost a line of space.
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(w / 2, h * (16 + 15 * i) / 100, Graphics.FONT_SMALL, lines[i],
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.drawText(w / 2, h * 88 / 100, Graphics.FONT_TINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // What the head unit itself reported, as opposed to what was typed in. A
    // mismatch between this and the Rear line is the usual sign of a cassette
    // entered with the wrong number of cogs.
    private function detected() as String {
        var cogs  = $.detectedRearCogs();
        var rings = $.chainringCount();
        var ringWord = (rings == 1) ? " ring" : " rings";
        if (cogs == null) {
            return "not seen yet";
        }
        return cogs.toString() + " cogs, " + rings.toString() + ringWord;
    }

    // Teeth as "38T" / "11..50 (11)" / "not set". Summarised by range and count
    // rather than listed: eleven values do not fit on a line, and range+count is
    // enough to spot a wrong or truncated entry.
    //
    // Always rendered SMALLEST..LARGEST, which is how drivetrains are described
    // everywhere ("11-50 cassette"), regardless of how the teeth are stored.
    // Internally the rear is held largest-first because position 1 is the
    // easiest gear — that ordering is load-bearing for the ratio lookup and must
    // not be "fixed" to match this display.
    private function summarise(teeth as Array<Number>) as String {
        var n = teeth.size();
        if (n == 0) {
            return "not set";
        } else if (n == 1) {
            return teeth[0].toString() + "T";
        }

        var smallest = teeth[0];
        var largest  = teeth[0];
        for (var i = 1; i < n; i++) {
            if (teeth[i] < smallest) {
                smallest = teeth[i];
            }
            if (teeth[i] > largest) {
                largest = teeth[i];
            }
        }
        return smallest.toString() + ".." + largest.toString() + " (" + n.toString() + ")";
    }
}

// Easiest to hardest, e.g. "0.92 - 4.27". Both ends come from the extreme
// tooth counts rather than from gear positions, so it does not depend on the
// bike being ridden or on which gear it is in.
function ratioRangeText(config as GearConfig) as String {
    var f = config.frontTeeth;
    var r = config.rearTeeth;
    if (f.size() == 0 || r.size() == 0) {
        return "not set";
    }
    var easiest = $.minTeeth(f).toFloat() / $.maxTeeth(r).toFloat();
    var hardest = $.maxTeeth(f).toFloat()  / $.minTeeth(r).toFloat();
    return easiest.format("%.2f") + " - " + hardest.format("%.2f");
}

function minTeeth(teeth as Array<Number>) as Number {
    var v = teeth[0];
    for (var i = 1; i < teeth.size(); i++) { if (teeth[i] < v) { v = teeth[i]; } }
    return v;
}

function maxTeeth(teeth as Array<Number>) as Number {
    var v = teeth[0];
    for (var i = 1; i < teeth.size(); i++) { if (teeth[i] > v) { v = teeth[i]; } }
    return v;
}
