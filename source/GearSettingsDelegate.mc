import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// On-device tooth-count wizard, ported from
// ../GarminGearRatio/source/GearSettingsDelegate.mc.
//
// Flow:  status view → front ring count → rear cog count → one picker per
//        ring, then one per cog → commit.
//
// Adapted from the original: GearRatio opens with a "Di2 profile" menu
// (1x11 / 2x12 / 2x13) because its ANT+ path can't see the drivetrain. Here the
// rear cog count is reported live by Activity.Info as rearDerailleurMax, so the
// cog-count menu pre-selects the last value the field actually saw rather than
// making the rider recall it. Front rings stays a question because a 1x bike
// reports 255/255 and tells us nothing.
//
// Nothing is written until the final picker is accepted — cancelling at any
// step leaves existing settings untouched.

// Drivetrain sizes most recently seen by the data field. The wizard normally
// runs outside an activity, when Activity.Info has no live values, so these are
// the only way it can know the drivetrain without asking.
//
// Both are detected: the cassette size directly (11 on this bike), and the
// chainring count by inference — a front derailleur reports its own max, so the
// 0xFF sentinel means there is none, i.e. a single ring. See
// StepsData.chainrings(). The FrontRings setting is the manual override for the
// case that inference gets wrong.
const LAST_REAR_MAX  = "LastRearMax";
const LAST_FRONT_MAX = "LastFrontMax";

// Detected cassette size, or null if the field has never seen one.
function detectedRearCogs() as Number? {
    var stored = Properties.getValue($.LAST_REAR_MAX);
    return (stored instanceof Lang.Number && stored >= 2) ? stored : null;
}

// Chainring count: what the bike reported, else the configured override, else 1.
function chainringCount() as Number {
    var detected = Properties.getValue($.LAST_FRONT_MAX);
    if (detected instanceof Lang.Number && detected >= 1 && detected <= 2) {
        return detected;
    }
    var configured = Properties.getValue("FrontRings");
    return (configured instanceof Lang.Number && configured >= 1) ? configured : 1;
}

// ── Tooth picker ─────────────────────────────────────────────────────────────
// A scrollable column of tooth counts 2..99. getValue() returns the tooth count
// itself, so CogPickerDelegate.onAccept() receives it directly.
class ToothPickerFactory extends WatchUi.PickerFactory {

    function initialize() {
        PickerFactory.initialize();
    }

    function getSize() as Number {
        return 98; // indices 0..97 → tooth counts 2..99
    }

    function getValue(index as Number) as Object? {
        return index + 2;
    }

    function getDrawable(index as Number, selected as Boolean) as WatchUi.Drawable? {
        return new WatchUi.Text({
            :text => (index + 2).toString() + "T",
            :color => Graphics.COLOR_WHITE,
            :font => Graphics.FONT_MEDIUM,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });
    }
}

// ── Wizard state ─────────────────────────────────────────────────────────────
// Accumulates every pick; commit() writes all three Properties at once.
class TeethEntry {

    var frontTotal as Number;
    var rearTotal  as Number;
    var frontTeeth as Array<Number>;
    var rearTeeth  as Array<Number>;

    // Saved teeth to prefill the pickers with, held in ENTRY order — smallest
    // first — not position order. The wizard walks sprockets the way riders
    // describe them ("11 up to 50"), while storage keeps position 1 as the
    // easiest gear. These two orders are reverses of each other at the rear, so
    // whoever fills these in must sort ascending; see startToothEntry.
    var existingFrontTeeth as Array<Number>;
    var existingRearTeeth  as Array<Number>;

    function initialize(frontTotal as Number, rearTotal as Number) {
        self.frontTotal = frontTotal;
        self.rearTotal  = rearTotal;
        self.frontTeeth = [] as Array<Number>;
        self.rearTeeth  = [] as Array<Number>;
        self.existingFrontTeeth = [] as Array<Number>;
        self.existingRearTeeth  = [] as Array<Number>;
    }

    // Starting value for the picker at (isRear, position): the saved value at
    // that position when reviewing, else `fallback` — the previous pick carried
    // forward, which saves re-scrolling from 2T on every cog.
    function startValueFor(isRear as Boolean, position as Number, fallback as Number?) as Number? {
        var existing = isRear ? existingRearTeeth : existingFrontTeeth;
        if (position < existing.size()) {
            return existing[position];
        }
        return fallback;
    }

    // Picks arrive smallest-first; sort into POSITION order before saving, so
    // position 1 is always the easiest gear — small ring, large cog. The sort
    // also means a mis-ordered entry still lands correctly.
    function commit() as Void {
        Properties.setValue("FrontRings", frontTotal);
        Properties.setValue("FrontTeeth", $.teethToCsv($.sortAscending(frontTeeth)));
        Properties.setValue("RearTeeth",  $.teethToCsv($.sortDescending(rearTeeth)));

        // onSettingsChanged() fires automatically only for settings pushed from
        // Garmin Connect. This wizard writes Properties directly, so the running
        // field's cached GearConfig would stay stale until restart. Poke it.
        (Application.getApp() as Di2StepsApp).onSettingsChanged();
    }
}

// ── Step 0: status screen ────────────────────────────────────────────────────
// OK goes straight to the tooth pickers, because the drivetrain is already
// known: the cassette size comes from the head unit and the ring count from
// settings. Only a bike the field has never seen ridden needs the cog-count
// question, and that is the sole reason RearCogsMenuDelegate still exists.
class GearSettingsDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var cogs = $.detectedRearCogs();
        if (cogs == null) {
            // Never ridden with this field installed, so nothing to go on.
            // Di2 was never built below 11-speed, so those are the only two
            // worth offering — a detected value is still used as-is, whatever
            // it turns out to be.
            var menu = new WatchUi.Menu2({:title => "Rear Cogs"});
            menu.addItem(new WatchUi.MenuItem("11-speed", "", 11, {}));
            menu.addItem(new WatchUi.MenuItem("12-speed", "", 12, {}));
            WatchUi.pushView(menu, new RearCogsMenuDelegate(), WatchUi.SLIDE_UP);
            return true;
        }
        $.startToothEntry($.chainringCount(), cogs, WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

// ── Fallback: cassette size, only when nothing was ever detected ─────────────
class RearCogsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (!(id instanceof Lang.Number)) {
            return;
        }
        $.startToothEntry($.chainringCount(), id as Number, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// ── Steps 3+: one picker per ring, then one per cog ──────────────────────────
class CogPickerDelegate extends WatchUi.PickerDelegate {

    private var _entry    as TeethEntry;
    private var _isRear   as Boolean;
    private var _position as Number;  // 0-based

    function initialize(entry as TeethEntry, isRear as Boolean, position as Number) {
        PickerDelegate.initialize();
        _entry    = entry;
        _isRear   = isRear;
        _position = position;
    }

    function onAccept(values as Array) as Boolean {
        var toothObj = values[0];
        if (!(toothObj instanceof Lang.Number)) {
            return true;
        }
        var tooth = toothObj as Number;

        if (_isRear) {
            _entry.rearTeeth.add(tooth);
        } else {
            _entry.frontTeeth.add(tooth);
        }

        var total   = _isRear ? _entry.rearTotal : _entry.frontTotal;
        var nextPos = _position + 1;

        if (nextPos < total) {
            // Carry the just-picked value forward as the next default: cassettes
            // and ring sets both step in one direction, so the next value is
            // always near this one.
            $.showToothPicker(_entry, _isRear, nextPos, _entry.startValueFor(_isRear, nextPos, tooth));
        } else if (!_isRear) {
            $.showToothPicker(_entry, true, 0, _entry.startValueFor(true, 0, null));
        } else {
            _entry.commit();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    // Cancel discards everything picked so far; saved settings are untouched.
    function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

// Build the wizard state for a known drivetrain and open the first picker.
// Prefills from the saved config when the topology matches, so re-running the
// wizard doubles as a review: page through accepting everything and nothing
// changes.
function startToothEntry(frontTotal as Number, rearTotal as Number, transition as WatchUi.SlideType) as Void {
    var entry = new TeethEntry(frontTotal, rearTotal);

    var current = new GearConfig();
    if (current.frontTeeth.size() == frontTotal && current.rearTeeth.size() == rearTotal) {
        // Stored in position order (rear largest-first); the pickers walk
        // smallest-first, so re-sort both into entry order. Without this the
        // rear would prefill backwards and "review" would rewrite the cassette.
        entry.existingFrontTeeth = $.sortAscending(current.frontTeeth);
        entry.existingRearTeeth  = $.sortAscending(current.rearTeeth);
    }

    var start = entry.startValueFor(false, 0, null);
    var options = $.toothPickerOptions(entry, false, 0, start);
    WatchUi.pushView(new WatchUi.Picker(options),
                     new CogPickerDelegate(entry, false, 0),
                     transition);
}

function toothPickerOptions(entry as TeethEntry, isRear as Boolean, position as Number, startValue as Number?) as Dictionary {
    var options = {
        :title => new WatchUi.Text({
            :text => $.toothPickerLabel(entry, isRear, position),
            :color => Graphics.COLOR_WHITE,
            :font => Graphics.FONT_TINY,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_BOTTOM
        }),
        :pattern => [new ToothPickerFactory()]
    };
    if (startValue != null) {
        // ToothPickerFactory.getValue(index) = index + 2, so invert it here.
        options[:defaults] = [(startValue as Number) - 2];
    }
    return options;
}

function showToothPicker(entry as TeethEntry, isRear as Boolean, position as Number, startValue as Number?) as Void {
    WatchUi.switchToView(new WatchUi.Picker($.toothPickerOptions(entry, isRear, position, startValue)),
                         new CogPickerDelegate(entry, isRear, position),
                         WatchUi.SLIDE_LEFT);
}

// Sprockets are entered smallest-first, the way drivetrains are described
// ("11-50 cassette"), so label the ends by SIZE rather than by gear difficulty.
// Saying "easiest"/"hardest" here would be actively misleading now that entry
// order is the reverse of position order at the rear.
function toothPickerLabel(entry as TeethEntry, isRear as Boolean, position as Number) as String {
    var step  = position + 1;
    var total = isRear ? entry.rearTotal : entry.frontTotal;

    if (!isRear && total == 1) {
        return "Front Ring";
    }

    var suffix = "";
    if (step == 1) {
        suffix = " (smallest)";
    } else if (step == total) {
        suffix = " (largest)";
    }
    return (isRear ? "Cog " : "Ring ") + step.toString() + " of " + total.toString() + suffix;
}
