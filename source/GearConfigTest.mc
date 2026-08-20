import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

// Unit tests for the tooth-count and ratio logic.
//
// This is the part of the app the simulator CAN prove. Gear positions come from
// Activity.Info, which has no simulated drivetrain behind it, but ratio() takes
// positions as plain parameters — so the whole arithmetic path is testable here
// without any hardware. Only the "what position are we in" half needs the bike.
//
// Run:  monkeyc -t -d edge1050 -f monkey.jungle -o bin/test.prg -y <key>
//       monkeydo bin/test.prg edge1050 -t

// ── parseTeethCsv ────────────────────────────────────────────────────────────

(:test)
function testParseEmpty(logger as Test.Logger) as Boolean {
    return $.parseTeethCsv("").size() == 0;
}

(:test)
function testParseSingle(logger as Test.Logger) as Boolean {
    var r = $.parseTeethCsv("38");
    return r.size() == 1 && r[0] == 38;
}

(:test)
function testParseElevenSpeedCassette(logger as Test.Logger) as Boolean {
    var r = $.parseTeethCsv("51,45,39,33,28,24,21,18,16,14,12");
    return r.size() == 11 && r[0] == 51 && r[10] == 12;
}

(:test)
function testParseSkipsNonNumericTokens(logger as Test.Logger) as Boolean {
    // Tokens that don't parse are dropped rather than becoming 0, which would
    // silently produce a divide-by-zero further down.
    var r = $.parseTeethCsv("38,,abc,12");
    return r.size() == 2 && r[0] == 38 && r[1] == 12;
}

// ── sortDescending: position 1 is the largest (easiest) cog ──────────────────

(:test)
function testSortDescendingNormalisesEntryOrder(logger as Test.Logger) as Boolean {
    // Rider typed the cassette smallest-first; position 1 must still be 51.
    var r = $.sortDescending([12, 14, 51, 28] as Array<Number>);
    return r[0] == 51 && r[1] == 28 && r[2] == 14 && r[3] == 12;
}

(:test)
function testSortDescendingDoesNotMutateInput(logger as Test.Logger) as Boolean {
    var input = [12, 51, 28] as Array<Number>;
    $.sortDescending(input);
    return input[0] == 12 && input[1] == 51 && input[2] == 28;
}

(:test)
function testSortDescendingSingleValue(logger as Test.Logger) as Boolean {
    var r = $.sortDescending([38] as Array<Number>);
    return r.size() == 1 && r[0] == 38;
}

// ── sortAscending: front position 1 is the small (easiest) ring ──────────────

(:test)
function testSortAscendingPutsSmallRingFirst(logger as Test.Logger) as Boolean {
    var r = $.sortAscending([50, 34] as Array<Number>);
    return r[0] == 34 && r[1] == 50;
}

// ── wizard entry order vs stored position order ──────────────────────────────
//
// The pickers walk sprockets smallest-first; storage keeps position 1 as the
// easiest gear (largest cog). Those are reverses of each other at the rear, so
// re-running the wizard as a review must round-trip exactly — otherwise paging
// through and accepting every value would silently reverse the cassette.

(:test)
function testReviewRoundTripPreservesRearOrder(logger as Test.Logger) as Boolean {
    var stored     = $.sortDescending([51, 45, 39, 33, 28, 24, 21, 18, 16, 14, 12] as Array<Number>);
    var entryOrder = $.sortAscending(stored);    // what the pickers prefill with
    var committed  = $.sortDescending(entryOrder); // what commit() writes back

    if (entryOrder[0] != 12 || entryOrder[10] != 51) {
        return false;   // pickers must start at the smallest cog
    }
    for (var i = 0; i < stored.size(); i++) {
        if (committed[i] != stored[i]) {
            return false;
        }
    }
    return true;
}

(:test)
function testReviewRoundTripPreservesFrontOrder(logger as Test.Logger) as Boolean {
    // Front storage is already ascending, so entry order matches it.
    var stored     = $.sortAscending([50, 34] as Array<Number>);
    var entryOrder = $.sortAscending(stored);
    var committed  = $.sortAscending(entryOrder);
    return entryOrder[0] == 34 && committed[0] == stored[0] && committed[1] == stored[1];
}

// ── teethToCsv round-trips through parseTeethCsv ─────────────────────────────

(:test)
function testTeethToCsvRoundTrip(logger as Test.Logger) as Boolean {
    var original = [51, 45, 39, 33, 28, 24, 21, 18, 16, 14, 12] as Array<Number>;
    var back = $.parseTeethCsv($.teethToCsv(original));
    if (back.size() != original.size()) {
        return false;
    }
    for (var i = 0; i < original.size(); i++) {
        if (back[i] != original[i]) {
            return false;
        }
    }
    return true;
}

(:test)
function testTeethToCsvEmpty(logger as Test.Logger) as Boolean {
    return $.teethToCsv([] as Array<Number>).equals("");
}

(:test)
function testTeethToCsvSingle(logger as Test.Logger) as Boolean {
    return $.teethToCsv([38] as Array<Number>).equals("38");
}

// ── inferChainrings: 0xFF means "no front derailleur", so one ring ───────────

(:test)
function testInferChainringsSentinelMeansOne(logger as Test.Logger) as Boolean {
    return $.inferChainrings(0xFF) == 1;
}

(:test)
function testInferChainringsDoubleReportsTwo(logger as Test.Logger) as Boolean {
    return $.inferChainrings(2) == 2;
}

(:test)
function testInferChainringsUnsampledIsNull(logger as Test.Logger) as Boolean {
    // Must stay distinct from "we know it's 1" so the wizard doesn't act on a
    // reading it never took.
    return $.inferChainrings(null) == null;
}

(:test)
function testInferChainringsRejectsZero(logger as Test.Logger) as Boolean {
    return $.inferChainrings(0) == null;
}

// ── Ride layout parity with Garmin's native fields ───────────────────────────
//
// Fonts and baselines come from the device's own datafield spec
// (Devices/edge1050/simulator.json). These tests pin the mapping so a future
// "tidy-up" can't quietly drift the field back out of parity.

function layoutDc() as Graphics.Dc {
    var bmp = Graphics.createBufferedBitmap({:width=>480, :height=>800}).get();
    return (bmp as Graphics.BufferedBitmap).getDc();
}

(:test)
function testNarrowSlotUsesGlanceAndHot(logger as Test.Logger) as Boolean {
    // 239x158 is the most common slot. Garmin uses glanceFont + simExtNumber3;
    // FONT_GLANCE is literally the same font, FONT_NUMBER_HOT within 3%.
    var dc = layoutDc();
    var L = $.computeRideLayout(dc, 239, 158, "RATIO", "2.04", "47:23");
    return L.labelFont == Graphics.FONT_GLANCE
        && L.valueFont == Graphics.FONT_NUMBER_HOT;
}

(:test)
function testNarrowSlotDropsTheFraction(logger as Test.Logger) as Boolean {
    // Garmin's data font runs to the bottom of these cells, so there is no room
    // beneath the number. Showing the fraction anyway is what made the field
    // look out of place.
    var dc = layoutDc();
    return !$.computeRideLayout(dc, 239, 158, "RATIO", "2.04", "47:23").showTeeth
        && !$.computeRideLayout(dc, 239, 160, "RATIO", "2.04", "47:23").showTeeth
        && !$.computeRideLayout(dc, 480, 158, "RATIO", "2.04", "47:23").showTeeth
        && !$.computeRideLayout(dc, 480, 198, "RATIO", "2.04", "47:23").showTeeth;
}

(:test)
function testTallSlotsKeepTheFraction(logger as Test.Logger) as Boolean {
    var dc = layoutDc();
    return $.computeRideLayout(dc, 480, 800, "RATIO", "2.04", "47:23").showTeeth
        && $.computeRideLayout(dc, 480, 399, "RATIO", "2.04", "47:23").showTeeth
        && $.computeRideLayout(dc, 480, 265, "RATIO", "2.04", "47:23").showTeeth;
}

(:test)
function testFractionFillsTheBandItIsGiven(logger as Test.Logger) as Boolean {
    // 480x399 (the 2-field slot) has 121px beneath the number. Picking the
    // first font that fits gave FONT_GLANCE at 37px, 4px under the number, with
    // ~80px of dead space below — reported on the road as too small and too
    // close. The largest font that fits is FONT_LARGE.
    var dc = layoutDc();
    var L = $.computeRideLayout(dc, 480, 399, "RATIO", "2.04", "47:23");
    return L.showTeeth && L.teethFont == Graphics.FONT_LARGE;
}

(:test)
function testFractionIsNotCrammedUnderTheNumber(logger as Test.Logger) as Boolean {
    // The gap above the fraction should be comparable to the gap below it, on
    // every slot that shows one — and the fraction must still land inside the
    // slot. A subscript hanging off the number is the failure this prevents.
    var dc = layoutDc();
    var sizes = [[480,800],[480,399],[480,318],[480,265]];
    for (var i = 0; i < sizes.size(); i++) {
        var h = sizes[i][1];
        var L = $.computeRideLayout(dc, sizes[i][0], h, "RATIO", "2.04", "47:23");
        if (!L.showTeeth) {
            return false;
        }
        var valueBottom = L.valueY + Graphics.getFontAscent(L.valueFont);
        var gap = L.teethY - valueBottom;
        var fh = dc.getFontHeight(L.teethFont);
        if (gap < 10 || gap > fh) {
            return false;
        }
        if (L.teethY + fh > h + 2) {
            return false;
        }
    }
    return true;
}

(:test)
function testValueSitsWhereGarminsWould(logger as Test.Logger) as Boolean {
    // 239x158: Garmin's data baseline is 135, and their font is 103% of ours, so
    // our glyphs are centred on their block rather than pinned to the baseline.
    // Where the fonts nearly match, the two rules agree within a pixel or two.
    var dc = layoutDc();
    var L = $.computeRideLayout(dc, 239, 158, "RATIO", "2.04", null);
    var expected = $.centredOnGarminsBlock(135, Graphics.getFontAscent(Graphics.FONT_NUMBER_HOT), 103);
    return L.valueY == expected
        && (L.valueY - (135 - Graphics.getFontAscent(Graphics.FONT_NUMBER_HOT))).abs() <= 2;
}

(:test)
function testLargeSlotNumberIsNotStrandedLow(logger as Test.Logger) as Boolean {
    // 480x318: Garmin's data font is 153% of ours. Pinning to their baseline
    // left our number floating at the bottom with a void beneath the label —
    // visibly wrong beside a native field. Centring on their block lifts it.
    var dc = layoutDc();
    var L = $.computeRideLayout(dc, 480, 318, "RATIO", "2.04", "47:23");
    var pinnedToBaseline = 256 - Graphics.getFontAscent(Graphics.FONT_NUMBER_THAI_HOT);
    return L.valueY < pinnedToBaseline - 15;
}

(:test)
function testUnknownSlotFallsBackToNearestHeight(logger as Test.Logger) as Boolean {
    // Another device, or a firmware that adds a size: a near neighbour still
    // looks native. 157 is one off 158.
    var dc = layoutDc();
    var L = $.computeRideLayout(dc, 239, 157, "RATIO", "2.04", null);
    return L.labelFont == Graphics.FONT_GLANCE && L.valueFont == Graphics.FONT_NUMBER_HOT;
}

(:test)
function testNothingIsPlacedAboveTheSlot(logger as Test.Logger) as Boolean {
    var dc = layoutDc();
    var sizes = [[480,800],[480,399],[480,318],[480,265],[480,198],[480,158],[239,160],[239,158]];
    for (var i = 0; i < sizes.size(); i++) {
        var L = $.computeRideLayout(dc, sizes[i][0], sizes[i][1], "RATIO", "2.04", "47:23");
        if (L.labelY < 0 || L.valueY < 0 || L.teethY < 0) {
            return false;
        }
    }
    return true;
}

// ── property access must not throw ───────────────────────────────────────────
//
// Properties.getValue() throws on a key that isn't declared in
// resources/properties.xml. In v1.0.8 the LastFrontMax constant existed and was
// read, but the declaration was missing, so the settings wizard crashed to the
// "IQ!" screen the instant it asked for the chainring count. Nothing caught it
// because no test touched Properties at all.
//
// These call every Properties-reading entry point. They assert little about the
// values — the point is that the call completes rather than throwing.

(:test)
function testDetectedRearCogsDoesNotThrow(logger as Test.Logger) as Boolean {
    var cogs = $.detectedRearCogs();
    return cogs == null || cogs >= 2;
}

(:test)
function testChainringCountDoesNotThrow(logger as Test.Logger) as Boolean {
    return $.chainringCount() >= 1;
}

(:test)
function testGearConfigLoadDoesNotThrow(logger as Test.Logger) as Boolean {
    var c = new GearConfig();   // initialize() calls load(), which reads 3 keys
    c.load();
    return c.frontRings >= 1;
}

// ── isPlausibleTeeth boundaries ──────────────────────────────────────────────

(:test)
function testPlausibleTeethBoundaries(logger as Test.Logger) as Boolean {
    return !$.isPlausibleTeeth(1)
        &&  $.isPlausibleTeeth(2)
        &&  $.isPlausibleTeeth(99)
        && !$.isPlausibleTeeth(100)
        && !$.isPlausibleTeeth(0);
}

// ── teeth lookup by position ─────────────────────────────────────────────────

function fixture() as GearConfig {
    var c = new GearConfig();
    c.frontTeeth = [38] as Array<Number>;
    c.rearTeeth  = $.sortDescending([51, 45, 39, 33, 28, 24, 21, 18, 16, 14, 12] as Array<Number>);
    c.frontRings = 1;
    return c;
}

(:test)
function testRearTeethPositionOneIsLargest(logger as Test.Logger) as Boolean {
    return fixture().rearTeethAt(1) == 51;
}

(:test)
function testRearTeethPositionElevenIsSmallest(logger as Test.Logger) as Boolean {
    return fixture().rearTeethAt(11) == 12;
}

(:test)
function testRearTeethMidRange(logger as Test.Logger) as Boolean {
    // Position 10 is what the bike reported on the 2026-08-09 ride.
    return fixture().rearTeethAt(10) == 14;
}

(:test)
function testTeethOutOfRangeIsNull(logger as Test.Logger) as Boolean {
    var c = fixture();
    return c.rearTeethAt(0) == null
        && c.rearTeethAt(12) == null
        && c.rearTeethAt(null) == null;
}

(:test)
function testTeethUnconfiguredIsNull(logger as Test.Logger) as Boolean {
    var c = new GearConfig();
    c.frontTeeth = [] as Array<Number>;
    c.rearTeeth  = [] as Array<Number>;
    return c.rearTeethAt(1) == null && c.frontTeethAt(1) == null;
}

// ── ratio ────────────────────────────────────────────────────────────────────

(:test)
function testRatioEasiestGear(logger as Test.Logger) as Boolean {
    // 38 / 51 = 0.745...
    var r = fixture().ratio(1, 1);
    return r != null && r.format("%.2f").equals("0.75");
}

(:test)
function testRatioHardestGear(logger as Test.Logger) as Boolean {
    // 38 / 12 = 3.1666...
    var r = fixture().ratio(1, 11);
    return r != null && r.format("%.2f").equals("3.17");
}

(:test)
function testRatioExactlyOne(logger as Test.Logger) as Boolean {
    var c = new GearConfig();
    c.frontTeeth = [24] as Array<Number>;
    c.rearTeeth  = [24] as Array<Number>;
    var r = c.ratio(1, 1);
    return r != null && r.format("%.2f").equals("1.00");
}

(:test)
function testRatioTwoDecimalRounding(logger as Test.Logger) as Boolean {
    // 48 / 18 = 2.6666... must render 2.67, not 2.66.
    var c = new GearConfig();
    c.frontTeeth = [48] as Array<Number>;
    c.rearTeeth  = [18] as Array<Number>;
    var r = c.ratio(1, 1);
    return r != null && r.format("%.2f").equals("2.67");
}

(:test)
function testRatioNullWhenUnconfigured(logger as Test.Logger) as Boolean {
    // Must be null, never 0.00 — a fabricated zero reads like a real value.
    var c = new GearConfig();
    c.frontTeeth = [] as Array<Number>;
    c.rearTeeth  = [] as Array<Number>;
    return c.ratio(1, 1) == null;
}

(:test)
function testRatioNullWhenPositionUnknown(logger as Test.Logger) as Boolean {
    // The bike reports 255/255 for the front on a 1x; that maps to null
    // position, which must not produce a ratio.
    return fixture().ratio(null, 10) == null;
}

// ── front position must never be invented from defaults ──────────────────────

// Activity.Info reports 255/255 for the front on this 1x bike, so these cover
// the config-derived fallback. FrontRings DEFAULTS to 1, so keying the fallback
// off it alone would fabricate "Position = 1" for an unconfigured rider.

function unconfiguredData() as StepsData {
    var d = new StepsData();
    d.supported = true;
    d.read      = true;
    d.frontIndex = 0xFF;   // no front derailleur present
    d.frontMax   = 0xFF;
    return d;
}

(:test)
function testFrontPositionNullWhenNoTeethConfigured(logger as Test.Logger) as Boolean {
    var c = new GearConfig();
    c.frontRings = 1;                        // the property default
    c.frontTeeth = [] as Array<Number>;      // but nothing entered
    return unconfiguredData().frontPosition(c) == null;
}

(:test)
function testFrontPositionOneWhenSingleRingConfigured(logger as Test.Logger) as Boolean {
    var c = new GearConfig();
    c.frontRings = 1;
    c.frontTeeth = [38] as Array<Number>;
    return unconfiguredData().frontPosition(c) == 1;
}

(:test)
function testFrontPositionNullForUnresolvedDoubleRing(logger as Test.Logger) as Boolean {
    // 2x with no live index: we cannot know which ring is engaged.
    var c = new GearConfig();
    c.frontRings = 2;
    c.frontTeeth = [50, 34] as Array<Number>;
    return unconfiguredData().frontPosition(c) == null;
}

(:test)
function testFrontPositionPrefersLiveValue(logger as Test.Logger) as Boolean {
    // If the head unit ever does report a front index, it wins over config.
    var d = unconfiguredData();
    d.frontIndex = 2;
    var c = new GearConfig();
    c.frontRings = 2;
    c.frontTeeth = [50, 34] as Array<Number>;
    return d.frontPosition(c) == 2;
}

(:test)
function testRearPositionRejectsSentinel(logger as Test.Logger) as Boolean {
    var d = new StepsData();
    d.supported = true;
    d.read      = true;
    d.rearIndex = 0xFF;
    return d.rearPosition() == null;
}

(:test)
function testRatioRisesWithPosition(logger as Test.Logger) as Boolean {
    // Position 1 is easiest, so the ratio must increase monotonically.
    var c = fixture();
    var previous = 0.0;
    for (var pos = 1; pos <= 11; pos++) {
        var r = c.ratio(1, pos);
        if (r == null || r <= previous) {
            return false;
        }
        previous = r;
    }
    return true;
}

// ── Configuration overview: ratio range ──────────────────────────────────────
//
// The settings screen's most useful line, and the one a rider would check a
// wrong cassette against. Derived from the extreme tooth counts, so it must not
// depend on gear position or on the order the teeth are stored in.

(:test)
function testRatioRangeSpansEasiestToHardest(logger as Test.Logger) as Boolean {
    var c = new GearConfig();
    c.frontTeeth = [47] as Array<Number>;
    c.rearTeeth  = $.sortDescending([51, 45, 39, 33, 28, 24, 21, 18, 16, 14, 12] as Array<Number>);
    // easiest 47/51 = 0.92, hardest 47/12 = 3.92
    return $.ratioRangeText(c).equals("0.92 - 3.92");
}

(:test)
function testRatioRangeIgnoresStorageOrder(logger as Test.Logger) as Boolean {
    var a = new GearConfig();
    a.frontTeeth = [34, 50] as Array<Number>;
    a.rearTeeth  = [30, 11] as Array<Number>;
    var b = new GearConfig();
    b.frontTeeth = [50, 34] as Array<Number>;
    b.rearTeeth  = [11, 30] as Array<Number>;
    return $.ratioRangeText(a).equals($.ratioRangeText(b))
        && $.ratioRangeText(a).equals("1.13 - 4.55");
}

(:test)
function testRatioRangeUnconfigured(logger as Test.Logger) as Boolean {
    var c = new GearConfig();
    if (!$.ratioRangeText(c).equals("not set")) {
        return false;
    }
    // One end configured is still not a range.
    c.frontTeeth = [47] as Array<Number>;
    return $.ratioRangeText(c).equals("not set");
}
