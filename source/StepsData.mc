import Toybox.Activity;
import Toybox.Application.Properties;
import Toybox.Lang;
import Toybox.System;

// Drivetrain state read from Toybox.Activity.Info.
//
// The head unit decodes the STEPS drivetrain from its own sensor pairing and
// hands the result to any data field, with no permission required. That is the
// app's only data source: the Shimano BLE path was removed on 2026-08-09 after
// an on-device ride showed it added nothing this field needs (see
// docs/project.md).
//
// Three states per field, and the difference matters when diagnosing:
//   supported == false  -> the API doesn't expose these fields on this device
//   read == false       -> not sampled yet (no activity running)
//   value == null       -> sampled, and the head unit had nothing to report
//
// Position fields track shifts correctly. The SIZE (teeth) fields do not: the
// rear reports a constant 12 regardless of gear and the front reports 0, so
// tooth counts come from GearConfig instead. Size is still captured here purely
// so the Test screen can show it — if a future firmware starts reporting real
// teeth, this is where it would show up first.
class StepsData {

    public var supported as Boolean = false;
    public var read      as Boolean = false;

    // ── Shift timing, for diagnosing render latency ───────────────────────────
    //
    // System.getTimer() (monotonic ms) at the moment sampling FIRST saw the
    // current rear position. onUpdate compares this against draw time to get the
    // gap between "we knew" and "the rider saw", which is the only part of the
    // delay this app controls — the gap between the physical shift and the head
    // unit reporting it is invisible to us and not measured here.
    public var rearChangedAtMs as Number = 0;
    private var _prevRearIndex as Number? = null;

    public var frontIndex as Number? = null;
    public var frontMax   as Number? = null;
    public var frontSize  as Number? = null;
    public var rearIndex  as Number? = null;
    public var rearMax    as Number? = null;
    public var rearSize   as Number? = null;

    function initialize() {
    }

    // Sample the derailleur fields. Guarded with `has` so a device or API level
    // without them degrades to "n/a" rather than throwing.
    function onActivityInfo(info as Activity.Info) as Void {
        if (!(info has :rearDerailleurIndex)) {
            supported = false;
            return;
        }
        supported = true;
        read      = true;

        frontIndex = info.frontDerailleurIndex;
        frontMax   = info.frontDerailleurMax;
        frontSize  = info.frontDerailleurSize;
        rearIndex  = info.rearDerailleurIndex;
        rearMax    = info.rearDerailleurMax;
        rearSize   = info.rearDerailleurSize;

        // Stamp the first sample that carries a new position. Both compute() and
        // onUpdate() call this, so whichever runs first wins — which is exactly
        // "the earliest moment we could have known".
        if (rearIndex != _prevRearIndex) {
            _prevRearIndex  = rearIndex;
            rearChangedAtMs = System.getTimer();
        }

        remember($.LAST_REAR_MAX, valid(rearMax));
        remember($.LAST_FRONT_MAX, $.inferChainrings(frontMax));
    }

    // Persist a detected drivetrain size the moment we see it. The settings
    // wizard normally runs with no activity recording, when Activity.Info has
    // nothing live, so this is the only way it can know the drivetrain without
    // asking the rider. Written only on change, to avoid a Properties write
    // every second.
    //
    // In practice the rear lands (11) and the front never does — a 1x bike
    // reports 0xFF, which valid() filters out.
    private function remember(key as String, max as Number?) as Void {
        if (max == null || max < 1) {
            return;
        }
        var stored = Properties.getValue(key);
        if (!(stored instanceof Number) || stored != max) {
            Properties.setValue(key, max);
        }
    }

    // 0xFF is the no-data sentinel, seen on the front of this 1x bike as
    // "255/255". Treat it as absent rather than as gear 255.
    private function valid(n as Number?) as Number? {
        return (n == null || n == 0xFF) ? null : n;
    }

    function rearPosition() as Number? {
        return valid(rearIndex);
    }

    // Front position. On a 1x drivetrain there is no front derailleur to
    // report, so Activity.Info sends 255/255 and the only possible source is
    // the rider's configuration.
    //
    // The fallback to position 1 requires the rider to have ACTUALLY ENTERED a
    // single chainring — frontRings alone is not enough, because it defaults to
    // 1 in properties.xml. Keying off the default would mean inventing
    // "Position = 1" for someone who has configured nothing, which is a
    // fabricated reading dressed up as data. Unconfigured must stay unknown.
    function frontPosition(config as GearConfig) as Number? {
        var live = valid(frontIndex);
        if (live != null) {
            return live;
        }
        if (config.frontRings == 1 && config.frontTeeth.size() == 1) {
            return 1;
        }
        return null;
    }
}
