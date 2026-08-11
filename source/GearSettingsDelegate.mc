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

// Property holding the most recent rearDerailleurMax seen by the data field.
// The wizard normally runs outside an activity, when Activity.Info has no live
// values, so this is the only way to offer a sensible default.
const LAST_REAR_MAX = "LastRearMax";

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

    // Populated when re-entering the same topology as the saved config, so each
    // picker starts on the currently saved value. That lets the wizard double
    // as a review pass: page through accepting everything and nothing changes.
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

    // Values may be picked in any order; sort into position order before saving
    // so position 1 is always the easiest gear — small ring, large cog.
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
class GearSettingsDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() as Boolean {
        var menu = new WatchUi.Menu2({:title => "Chainrings"});
        menu.addItem(new WatchUi.MenuItem("1x", "Single chainring", 1, {}));
        menu.addItem(new WatchUi.MenuItem("2x", "Double chainring", 2, {}));
        WatchUi.pushView(menu, new FrontRingsMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

// ── Step 1: how many chainrings ──────────────────────────────────────────────
class FrontRingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (!(id instanceof Lang.Number)) {
            return;
        }
        var frontTotal = id as Number;

        // Offer cog counts, marking the one the field last saw on the bike.
        var lastMax = Properties.getValue(LAST_REAR_MAX);
        var menu = new WatchUi.Menu2({:title => "Rear Cogs"});
        for (var cogs = 9; cogs <= 13; cogs++) {
            var note = (lastMax instanceof Lang.Number && lastMax == cogs)
                ? "detected on bike" : "";
            menu.addItem(new WatchUi.MenuItem(cogs.toString() + "-speed", note, cogs, {}));
        }
        WatchUi.pushView(menu, new RearCogsMenuDelegate(frontTotal), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// ── Step 2: how many cogs, then straight into the pickers ────────────────────
class RearCogsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _frontTotal as Number;

    function initialize(frontTotal as Number) {
        Menu2InputDelegate.initialize();
        _frontTotal = frontTotal;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (!(id instanceof Lang.Number)) {
            return;
        }
        var entry = new TeethEntry(_frontTotal, id as Number);

        // Same topology as what's saved → prefill, so this doubles as a review.
        // A different topology starts fresh; old teeth wouldn't line up anyway.
        var current = new GearConfig();
        if (current.frontTeeth.size() == entry.frontTotal
            && current.rearTeeth.size() == entry.rearTotal) {
            entry.existingFrontTeeth = current.frontTeeth;
            entry.existingRearTeeth  = current.rearTeeth;
        }

        $.showToothPicker(entry, false, 0, entry.startValueFor(false, 0, null));
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

function showToothPicker(entry as TeethEntry, isRear as Boolean, position as Number, startValue as Number?) as Void {
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
    WatchUi.switchToView(new WatchUi.Picker(options),
                         new CogPickerDelegate(entry, isRear, position),
                         WatchUi.SLIDE_LEFT);
}

// Position 1 is the easiest gear, so label the ends rather than leaving the
// rider to guess which way the cassette is being walked.
function toothPickerLabel(entry as TeethEntry, isRear as Boolean, position as Number) as String {
    var pos1 = position + 1;
    if (!isRear) {
        if (entry.frontTotal == 1) {
            return "Front Ring";
        }
        return "Ring " + pos1.toString() + " of " + entry.frontTotal.toString();
    }
    var suffix = "";
    if (pos1 == 1) {
        suffix = " (easiest)";
    } else if (pos1 == entry.rearTotal) {
        suffix = " (hardest)";
    }
    return "Cog " + pos1.toString() + " of " + entry.rearTotal.toString() + suffix;
}
