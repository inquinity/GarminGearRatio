import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Shown when the rider opens this data field's settings on the device.
// Reports what is currently configured; OK starts the wizard, Back exits.
//
// Ported from ../GarminGearRatio/source/GearSettingsView.mc. Adapted: that app
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

        var frontLine = "Front: " + summarise(config.frontTeeth);
        var rearLine  = "Rear: "  + summarise(config.rearTeeth);
        var hint      = configured ? "Press OK to change" : "Press OK to set up";

        dc.drawText(w / 2, h / 8,     Graphics.FONT_TINY,  "Di2 STEPS Gears", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 3 / 8, Graphics.FONT_SMALL, frontLine,         Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 5 / 8, Graphics.FONT_SMALL, rearLine,          Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 7 / 8, Graphics.FONT_TINY,  hint,              Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Teeth as "38T" / "51..12 (11)" / "not set". The rear is summarised by its
    // range and count rather than listed: eleven values do not fit on a line,
    // and range+count is enough to spot a wrong or truncated entry.
    private function summarise(teeth as Array<Number>) as String {
        var n = teeth.size();
        if (n == 0) {
            return "not set";
        } else if (n == 1) {
            return teeth[0].toString() + "T";
        }
        return teeth[0].toString() + ".." + teeth[n - 1].toString() + " (" + n.toString() + ")";
    }
}
