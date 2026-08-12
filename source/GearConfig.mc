import Toybox.Application.Properties;
import Toybox.Lang;

// Drivetrain tooth counts, entered by the rider in app settings.
//
// These MUST be user-entered. Activity.Info exposes frontDerailleurSize and
// rearDerailleurSize in teeth, but on the SC-EM800 they are useless for this:
// the rear reports a constant (12 observed across every gear, never changing
// with position) and the front reports 0. Verified on-device 2026-08-09 — see
// docs/project.md. Only the POSITION fields track shifts.
//
// parseTeethCsv is ported from v1 (../GarminGearRatioVersion1), which solves
// the same problem from a raw ANT+ Di2 channel.
//
// INDEX CONVENTION — **rear position 1 is the easiest gear, i.e. the LARGEST
// cog**, descending to the smallest at position 11. Two independent sources
// agree: the rider confirmed it on this bike (2026-08-09), and v1's DESIGN.md
// derives the same rule from ki2's tests against real Di2 hardware — see
// docs/GearRatioV1-DESIGN.md § "Entry order and sorting".
//
// v1's code agrees too. Its *comments* on sortAscending/sortDescending were
// swapped and briefly suggested otherwise; that was a documentation bug, since
// fixed there. Don't reintroduce the confusion by "correcting" this to match a
// stale reading.
//
// Because the mapping is monotonic by physics, rear teeth are sorted
// largest-first on load. Entry order therefore cannot silently produce a
// wrong ratio.

// Parse a comma-separated string of integers into an Array<Number>.
// Tokens that don't parse as integers are silently skipped.
function parseTeethCsv(csv as String) as Array<Number> {
    var result = [] as Array<Number>;
    var len = csv.length();
    var start = 0;
    for (var i = 0; i <= len; i++) {
        var ch = (i < len) ? csv.substring(i, i + 1) : ",";
        if (ch != null && ch.equals(",")) {
            var part = csv.substring(start, i);
            if (part != null) {
                var n = part.toNumber();
                if (n != null) {
                    result.add(n);
                }
            }
            start = i + 1;
        }
    }
    return result;
}

// A plausible bicycle sprocket. Rejects transcription slips like "0" or "380".
function isPlausibleTeeth(t as Number) as Boolean {
    return t >= 2 && t <= 99;
}

// Sorted smallest-first. Front position 1 is the easiest gear — the SMALL ring
// — so chainrings ascend by position. Only matters for 2x; a single ring sorts
// to itself.
function sortAscending(teeth as Array<Number>) as Array<Number> {
    var sorted = [] as Array<Number>;
    sorted.addAll(teeth);
    sorted.sort(null);
    return sorted;
}

// Sorted largest-first. Rear position 1 is the easiest gear (largest cog), so
// this maps entry order onto position order regardless of how the rider typed
// the CSV. Cassette tooth counts are strictly decreasing by position, so this
// is a normalisation, not a guess.
function sortDescending(teeth as Array<Number>) as Array<Number> {
    return sortAscending(teeth).reverse() as Array<Number>;
}

// Number of chainrings, inferred from Activity.Info's frontDerailleurMax.
//
// A front derailleur that exists reports its own max (2 for a double), so the
// 0xFF no-data sentinel means there is no front derailleur to report — i.e. a
// single ring. This is an inference, not a documented guarantee: a 2x that
// failed to report would be read as 1x. There is no way to distinguish those,
// and the FrontRings setting stays available as a manual override.
//
// Returns null when nothing has been sampled, so callers can tell "we don't
// know yet" from "we know it's 1".
function inferChainrings(frontMax as Number?) as Number? {
    if (frontMax == null) {
        return null;
    } else if (frontMax == 0xFF) {
        return 1;
    }
    return (frontMax >= 1) ? frontMax : null;
}

// Should the Ride screen put the ratio and tooth pair SIDE BY SIDE rather than
// stacking them? True for wide strips, where there is width to spare and no
// height for a second line.
//
// The threshold is 2.6:1, chosen against the Edge 1050's actual slot geometry
// (Devices/edge1050/simulator.json — 24 layouts, 17 distinct sizes): it catches
// the wide strips at ~3.0 and leaves 480x198 (2.42) and 480x265 (1.81) stacked,
// since those have the height for a big number plus a small line. Kept here as
// a free function so it can be tested against every real slot size.
function ridePrefersSideBySide(width as Number, height as Number) as Boolean {
    if (height <= 0) {
        return false;
    }
    return (width * 10) / height >= 26;
}

// Render teeth back to the CSV form stored in Properties.
function teethToCsv(teeth as Array<Number>) as String {
    var s = "";
    for (var i = 0; i < teeth.size(); i++) {
        if (i > 0) {
            s = s + ",";
        }
        s = s + teeth[i].toString();
    }
    return s;
}

// Tooth counts loaded from application Properties.
//
// Unlike GearRatio's equivalent, this does NOT validate the rear count against
// a configured cassette size: rearDerailleurMax arrives live from Activity.Info
// (11 on this bike), so the expected count isn't known until the head unit
// reports it. Validation is therefore per-lookup rather than up front, which
// also means a partially-filled config still shows whatever it can.
class GearConfig {

    public var frontTeeth as Array<Number> = [] as Array<Number>;
    public var rearTeeth  as Array<Number> = [] as Array<Number>;
    public var frontRings as Number        = 1;

    function initialize() {
        load();
    }

    function load() as Void {
        var rings = Properties.getValue("FrontRings");
        frontRings = (rings instanceof Number && rings > 0) ? rings : 1;

        var frontStr = Properties.getValue("FrontTeeth");
        var rearStr  = Properties.getValue("RearTeeth");

        // Position 1 is the easiest gear on both axes: small ring at the front,
        // large cog at the rear. Sorting on load means a hand-typed CSV in any
        // order maps onto positions correctly.
        frontTeeth = sortAscending(parseTeethCsv(frontStr instanceof String ? frontStr : ""));
        rearTeeth  = sortDescending(parseTeethCsv(rearStr instanceof String ? rearStr : ""));
    }

    // Teeth for a 1-based gear position, or null when unconfigured or out of
    // range. Null is a real answer here — it means "the rider hasn't told us" —
    // and the caller renders it distinctly rather than substituting a guess.
    private function teethAt(teeth as Array<Number>, position as Number?) as Number? {
        if (position == null || position < 1 || position > teeth.size()) {
            return null;
        }
        var t = teeth[position - 1];
        return isPlausibleTeeth(t) ? t : null;
    }

    function frontTeethAt(position as Number?) as Number? {
        return teethAt(frontTeeth, position);
    }

    function rearTeethAt(position as Number?) as Number? {
        return teethAt(rearTeeth, position);
    }

    // Gear ratio: front teeth / rear teeth. This is the "power multiplier" —
    // how far the wheel turns per crank revolution. Null when either end is
    // unconfigured, so the UI can say so instead of showing a fabricated 0.00.
    function ratio(frontPos as Number?, rearPos as Number?) as Float? {
        var tf = frontTeethAt(frontPos);
        var tr = rearTeethAt(rearPos);
        if (tf == null || tr == null || tr == 0) {
            return null;
        }
        return tf.toFloat() / tr.toFloat();
    }
}
