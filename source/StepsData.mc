import Toybox.Activity;
import Toybox.Lang;

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
    }

    // 0xFF is the no-data sentinel, seen on the front of this 1x bike as
    // "255/255". Treat it as absent rather than as gear 255.
    private function valid(n as Number?) as Number? {
        return (n == null || n == 0xFF) ? null : n;
    }

    function rearPosition() as Number? {
        return valid(rearIndex);
    }

    // Front position, with a fallback that matters on a 1x drivetrain: there is
    // no front derailleur to report, so Activity.Info sends 255/255. If the
    // rider has configured a single chainring, position 1 is the only
    // possibility and is more useful than showing nothing.
    function frontPosition(config as GearConfig) as Number? {
        var live = valid(frontIndex);
        if (live != null) {
            return live;
        }
        return (config.frontRings == 1) ? 1 : null;
    }
}
