import Toybox.Graphics;
import Toybox.Lang;

// Ride-screen geometry, matched to Garmin's own data fields.
//
// GUIDING PRINCIPLE: parity. A Connect IQ field sitting next to native fields
// should look like one of them, not like a visitor. So rather than inventing
// sizes and positions, this reproduces what the device itself specifies for a
// native field in the same slot.
//
// Everything below is lifted from the device definition:
//   ~/Library/Application Support/Garmin/ConnectIQ/Devices/edge1050/simulator.json
//     layouts[0].datafields.datafields[].fields[]
// which gives, per slot size, the label font, the data font, and the BASELINE y
// of each — slot-relative, identical for every instance of a given size.
//
// Font mapping (Garmin's internal name → nearest Connect IQ font, by the `size`
// values in that same file's `fonts` section):
//
//   glanceFont     8.43  → FONT_GLANCE          8.43   IDENTICAL FONT
//   simExtNumber3 25.65  → FONT_NUMBER_HOT     24.92   -3%
//   simExtNumber5 14.66  → FONT_LARGE          15.57   +6%
//   simExtNumber7 32.98  → FONT_NUMBER_THAI_HOT 31.15  -6%
//   simExtNumber1 18.32  → FONT_LARGE          15.57  -15%
//   simExtNumber8 43.97  → FONT_NUMBER_THAI_HOT 31.15 -29%  cannot match
//   simExtNumber4 47.64  → FONT_NUMBER_THAI_HOT 31.15 -35%  cannot match
//
// The last two are a platform limit, not a choice: Garmin's private data fonts
// for large slots are bigger than anything Connect IQ exposes. On the narrow and
// strip slots — 79 of the 105 field instances across all layouts — parity is
// essentially exact.
//
// BASELINES, not tops. Connect IQ's drawText takes the top of the text box, so
// each y here is converted with `baseline - getFontAscent(font)`. The box then
// extends `descent` past the baseline, which can exceed the slot; that region is
// empty for digits, so nothing clips. Aligning baselines is what puts our number
// on the same line as the neighbouring native field.
class RideLayout {
    public var valueFont as Graphics.FontDefinition = Graphics.FONT_NUMBER_HOT;
    public var labelFont as Graphics.FontDefinition = Graphics.FONT_GLANCE;
    public var teethFont as Graphics.FontDefinition = Graphics.FONT_XTINY;

    public var showLabel as Boolean = true;
    public var showTeeth as Boolean = false;

    public var labelY as Number = 0;
    public var valueY as Number = 0;
    public var teethY as Number = 0;

    function initialize() {
    }
}

// Font identifiers used by the slot table below.
const PF_GLANCE    = 0;   // glanceFont
const PF_LARGE     = 1;   // simExtNumber1 / simExtNumber5
const PF_HOT       = 2;   // simExtNumber3
const PF_THAI_HOT  = 3;   // simExtNumber4 / 7 / 8

function parityFont(id as Number) as Graphics.FontDefinition {
    if (id == $.PF_GLANCE)   { return Graphics.FONT_GLANCE; }
    if (id == $.PF_LARGE)    { return Graphics.FONT_LARGE; }
    if (id == $.PF_HOT)      { return Graphics.FONT_NUMBER_HOT; }
    return Graphics.FONT_NUMBER_THAI_HOT;
}

// One row per distinct slot size the Edge 1050 offers:
//   [ width, height, labelFontId, labelBaselineY, labelScale%,
//                    valueFontId, valueBaselineY, valueScale% ]
//
// The scale is Garmin's font size as a percentage of ours, from the `fonts`
// section of the same file. It exists because we cannot always match their
// size: where their font is larger, their glyphs occupy a taller block above
// the baseline, and pinning our smaller glyphs to that same baseline leaves a
// void above the number. Instead we centre our block where theirs sits — see
// centredOnGarminsBlock(). Where the fonts nearly match (100-106%) this is
// within a pixel or two of plain baseline alignment.
//
//   glanceFont/FONT_GLANCE          100%    simExtNumber3/NUMBER_HOT   103%
//   simExtNumber5/FONT_LARGE         94%    simExtNumber7/THAI_HOT     106%
//   simExtNumber1/FONT_LARGE        118%    simExtNumber8/THAI_HOT     141%
//                                           simExtNumber4/THAI_HOT     153%
//
// All 17 sizes are listed verbatim rather than derived; 239 and 480 variants
// differ slightly in baseline, not only in x-centre.
const PARITY_SLOTS = [
    [480, 800, $.PF_LARGE,  340, 118, $.PF_THAI_HOT, 507, 153],
    [480, 399, $.PF_LARGE,  139, 118, $.PF_THAI_HOT, 306, 153],
    [480, 319, $.PF_LARGE,   97,  94, $.PF_THAI_HOT, 256, 153],
    [480, 318, $.PF_LARGE,   97,  94, $.PF_THAI_HOT, 256, 153],
    [480, 316, $.PF_LARGE,   96,  94, $.PF_THAI_HOT, 255, 153],
    [480, 266, $.PF_LARGE,   76,  94, $.PF_THAI_HOT, 225, 141],
    [480, 265, $.PF_LARGE,   76,  94, $.PF_THAI_HOT, 225, 141],
    [480, 200, $.PF_LARGE,   59,  94, $.PF_THAI_HOT, 178, 106],
    [480, 198, $.PF_LARGE,   59,  94, $.PF_THAI_HOT, 178, 106],
    [480, 162, $.PF_GLANCE,  44, 100, $.PF_HOT,      131, 103],
    [480, 160, $.PF_GLANCE,  44, 100, $.PF_HOT,      131, 103],
    [480, 159, $.PF_GLANCE,  45, 100, $.PF_HOT,      136, 103],
    [480, 158, $.PF_GLANCE,  44, 100, $.PF_HOT,      131, 103],
    [239, 162, $.PF_GLANCE,  44, 100, $.PF_HOT,      135, 103],
    [239, 160, $.PF_GLANCE,  44, 100, $.PF_HOT,      135, 103],
    [239, 159, $.PF_GLANCE,  45, 100, $.PF_HOT,      136, 103],
    [239, 158, $.PF_GLANCE,  44, 100, $.PF_HOT,      135, 103]
];

// Top y for drawText so our glyphs sit centred where Garmin's would.
//
// Digits have no descender, so a native value visually occupies
// [baseline - theirAscent, baseline]. We centre our own [y, y + ourAscent] on
// the middle of that. When the fonts match, this collapses to
// `baseline - ourAscent`, i.e. plain baseline alignment.
function centredOnGarminsBlock(baseline as Number, ourAscent as Number, scalePct as Number) as Number {
    var theirAscent = (ourAscent * scalePct) / 100;
    var theirCentre = baseline - theirAscent / 2;
    return theirCentre - ourAscent / 2;
}

// Row for this slot: exact match, else the closest by height. The fallback
// matters for other devices and for future firmware that adds a size — a near
// neighbour still looks native, where inventing a layout would not.
function parityRowFor(width as Number, height as Number) as Array<Number> {
    var best = $.PARITY_SLOTS[0];
    var bestScore = 999999;
    for (var i = 0; i < $.PARITY_SLOTS.size(); i++) {
        var row = $.PARITY_SLOTS[i];
        if (row[0] == width && row[1] == height) {
            return row;
        }
        // Height dominates: it decides the font tier. Width only separates the
        // half-width column from the full-width one.
        var score = (height - row[1]).abs() + ((width - row[0]).abs() > 100 ? 500 : 0);
        if (score < bestScore) {
            bestScore = score;
            best = row;
        }
    }
    return best;
}

// Lay out the Ride screen for a slot of w x h, in slot coordinates.
//
// `teeth` is drawn only where Garmin's own geometry leaves room beneath the
// number. On the narrow and strip slots the native data font runs to the bottom
// of the cell, so there is none — the fraction is dropped rather than shrunk
// into the margin, because parity beats completeness here.
function computeRideLayout(dc as Graphics.Dc, w as Number, h as Number,
                           label as String, value as String, teeth as String?) as RideLayout {
    var out = new RideLayout();
    var row = $.parityRowFor(w, h);

    out.labelFont = $.parityFont(row[2]);
    out.valueFont = $.parityFont(row[5]);
    out.showLabel = true;

    var labelAscent = Graphics.getFontAscent(out.labelFont);
    var valueAscent = Graphics.getFontAscent(out.valueFont);

    out.labelY = $.centredOnGarminsBlock(row[3], labelAscent, row[4]);
    out.valueY = $.centredOnGarminsBlock(row[6], valueAscent, row[7]);

    if (out.labelY < 0) {
        out.labelY = 0;
    }
    if (out.valueY < 0) {
        out.valueY = 0;
    }

    if (teeth != null) {
        // Space beneath OUR glyphs, not Garmin's baseline: on the large slots
        // our smaller number sits higher, and that is exactly where the room
        // for a fraction comes from.
        var valueBottom = out.valueY + valueAscent;
        var below = h - valueBottom;

        // Largest font that fits the band, not the first one that does. On the
        // 2-field slot the band is 121px tall, so settling for FONT_GLANCE (37)
        // rendered the fraction as a subscript with 80px of void under it —
        // reported on the road 2026-08-14 as "too close and too small".
        //
        // FONT_SMALL is still the floor. Anything smaller is unreadable at
        // arm's length on a moving bike, and cramming it into a few spare
        // pixels is precisely the "doesn't belong here" look that parity is
        // meant to remove — a narrow slot shows nothing there instead.
        var candidates = [
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_GLANCE,
            Graphics.FONT_SMALL
        ];
        for (var i = 0; i < candidates.size(); i++) {
            var f = candidates[i];
            var fh = dc.getFontHeight(f);
            if (fh + 6 <= below && dc.getTextWidthInPixels(teeth, f) <= w) {
                out.teethFont = f;
                out.showTeeth = true;

                // Centred in the band, so the gap above the fraction matches
                // the gap below it and the pair reads as two deliberate
                // elements rather than a number with a tail.
                //
                // Capped at the fraction's own height because the band grows
                // without bound: on the full-screen 480x800 slot centring
                // alone would leave a 130px gap and the fraction would stop
                // looking related to the number above it.
                var gap = (below - fh) / 2;
                if (gap > fh) {
                    gap = fh;
                }
                out.teethY = valueBottom + gap;
                break;
            }
        }
    }

    return out;
}
