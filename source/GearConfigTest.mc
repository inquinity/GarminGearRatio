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
