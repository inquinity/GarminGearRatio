import Toybox.Graphics;
import Toybox.Lang;

// Geometry for the Ride screen, computed separately from drawing so it can be
// probed and tested at every real slot size without a device.
//
// The whole point of this class is that label + value + teeth are laid out as
// ONE GROUP and that group is centred in the slot. The previous version centred
// each element inside its own horizontal band, which on a 480x800 screen threw
// the ratio and the teeth to opposite ends with a void between them.
class RideLayout {
    public var valueFont as Graphics.FontDefinition = Graphics.FONT_XTINY;
    public var labelFont as Graphics.FontDefinition = Graphics.FONT_XTINY;
    public var teethFont as Graphics.FontDefinition = Graphics.FONT_XTINY;

    public var showLabel as Boolean = false;
    public var showTeeth as Boolean = false;

    // Top y of each element, already centred as a group within the slot.
    public var labelY as Number = 0;
    public var valueY as Number = 0;
    public var teethY as Number = 0;

    function initialize() {
    }
}

// Value font ladder, smallest → largest. The NUMBER_* fonts are what Garmin's
// own data fields use; the text fonts stop at 61px, which is why this field
// looked lost in its slot before. NUMBER_* glyph sets cover digits, ".", ":"
// and "-" only — fine for "2.76" and "47:17", useless for a label.
const RIDE_VALUE_FONTS = [
    Graphics.FONT_XTINY,
    Graphics.FONT_TINY,
    Graphics.FONT_SMALL,
    Graphics.FONT_MEDIUM,
    Graphics.FONT_LARGE,
    Graphics.FONT_NUMBER_MILD,
    Graphics.FONT_NUMBER_MEDIUM,
    Graphics.FONT_NUMBER_HOT,
    Graphics.FONT_NUMBER_THAI_HOT
];

// Label and teeth sizes paired to each value font, indexed to match
// RIDE_VALUE_FONTS. Subordinate text scales WITH the number rather than with
// the slot: sizing it off slot height alone produced a 21px fraction under a
// 136px ratio, which was unreadable, and a 28px label on a full screen, which
// was lost.
//
// The pairing also means the layout would rather step the number down one font
// than shrink its annotations into illegibility — so a 480x198 slot takes a
// 109px ratio with a 38px fraction over a 136px ratio with a 21px one.
const RIDE_LABEL_FONTS = [
    Graphics.FONT_XTINY,   // XTINY
    Graphics.FONT_XTINY,   // TINY
    Graphics.FONT_XTINY,   // SMALL
    Graphics.FONT_XTINY,   // MEDIUM
    Graphics.FONT_XTINY,   // LARGE
    Graphics.FONT_XTINY,   // NUMBER_MILD    71px
    Graphics.FONT_XTINY,   // NUMBER_MEDIUM  82px
    Graphics.FONT_SMALL,   // NUMBER_HOT    109px
    Graphics.FONT_MEDIUM   // NUMBER_THAI_HOT 136px
];

const RIDE_TEETH_FONTS = [
    Graphics.FONT_XTINY,
    Graphics.FONT_XTINY,
    Graphics.FONT_XTINY,
    Graphics.FONT_XTINY,
    Graphics.FONT_XTINY,
    Graphics.FONT_TINY,    // NUMBER_MILD     71px → 28px
    Graphics.FONT_SMALL,   // NUMBER_MEDIUM   82px → 33px
    Graphics.FONT_MEDIUM,  // NUMBER_HOT     109px → 38px
    Graphics.FONT_MEDIUM   // NUMBER_THAI_HOT 136px → 38px
];

// Below this the number is small enough that annotations stop earning their
// space. 3 = FONT_MEDIUM.
const RIDE_MIN_BARE = 3;

const RIDE_GAP = 4;

// Largest value font whose height fits `budget` and whose rendering of `text`
// fits `width`. Returns an index into RIDE_VALUE_FONTS, or -1 if none fit.
function rideFitValue(dc as Graphics.Dc, text as String, width as Number, budget as Number) as Number {
    var best = -1;
    for (var i = 0; i < $.RIDE_VALUE_FONTS.size(); i++) {
        var f = $.RIDE_VALUE_FONTS[i];
        if (dc.getFontHeight(f) <= budget && dc.getTextWidthInPixels(text, f) <= width) {
            best = i;
        }
    }
    return best;
}

// Lay out the Ride screen inside a w×h box.
//
// Tries the full group first, then sheds the teeth, then the label — always
// protecting the number, because the ratio is the reason the field exists.
function computeRideLayout(dc as Graphics.Dc, w as Number, h as Number,
                           label as String, value as String, teeth as String?) as RideLayout {
    var out = new RideLayout();

    // Three passes, each walking the value fonts from largest down. Shedding an
    // element is a LAST resort — a smaller ratio with a readable fraction beats
    // a huge ratio with none, which is why the whole group is tried at every
    // size before pass 2 begins.
    var i;

    // Pass 1: label + value + teeth.
    if (teeth != null) {
        for (i = $.RIDE_VALUE_FONTS.size() - 1; i >= $.RIDE_MIN_BARE; i--) {
            var vFont = $.RIDE_VALUE_FONTS[i];
            var lFont = $.RIDE_LABEL_FONTS[i];
            var tFont = $.RIDE_TEETH_FONTS[i];
            var vH = dc.getFontHeight(vFont);
            var lH = dc.getFontHeight(lFont);
            var tH = dc.getFontHeight(tFont);
            var total = lH + $.RIDE_GAP + vH + $.RIDE_GAP + tH;
            if (total <= h
                && dc.getTextWidthInPixels(value, vFont) <= w
                && dc.getTextWidthInPixels(teeth, tFont) <= w) {
                out.valueFont = vFont;
                out.labelFont = lFont;
                out.teethFont = tFont;
                out.showLabel = true;
                out.showTeeth = true;
                out.labelY = (h - total) / 2;
                out.valueY = out.labelY + lH + $.RIDE_GAP;
                out.teethY = out.valueY + vH + $.RIDE_GAP;
                return out;
            }
        }
    }

    // Pass 2: label + value. The fraction goes first — it confirms configuration,
    // which matters far less at a glance than the ratio itself.
    for (i = $.RIDE_VALUE_FONTS.size() - 1; i >= $.RIDE_MIN_BARE; i--) {
        var vFont2 = $.RIDE_VALUE_FONTS[i];
        var lFont2 = $.RIDE_LABEL_FONTS[i];
        var vH2 = dc.getFontHeight(vFont2);
        var lH2 = dc.getFontHeight(lFont2);
        var total2 = lH2 + $.RIDE_GAP + vH2;
        if (total2 <= h && dc.getTextWidthInPixels(value, vFont2) <= w) {
            out.valueFont = vFont2;
            out.labelFont = lFont2;
            out.showLabel = true;
            out.labelY = (h - total2) / 2;
            out.valueY = out.labelY + lH2 + $.RIDE_GAP;
            return out;
        }
    }

    // Pass 3: the number alone, as large as will fit.
    for (i = $.RIDE_VALUE_FONTS.size() - 1; i >= 0; i--) {
        var vFont3 = $.RIDE_VALUE_FONTS[i];
        var vH3 = dc.getFontHeight(vFont3);
        if (vH3 <= h && dc.getTextWidthInPixels(value, vFont3) <= w) {
            out.valueFont = vFont3;
            out.valueY = (h - vH3) / 2;
            return out;
        }
    }

    // Nothing fits at all — smallest font, centred, and let it clip.
    out.valueFont = $.RIDE_VALUE_FONTS[0];
    out.valueY = (h - dc.getFontHeight(out.valueFont)) / 2;
    return out;
}
