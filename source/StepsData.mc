import Toybox.Lang;
import Toybox.StringUtil;

// Decoded state from the SC-EM800's multiplexed 2AC1 characteristic, plus a
// small ring of the last raw packet seen per type-tag for the TEST screen.
//
// Wire format is documented in SCEM800-BLE-protocol.md. Each notification's
// FIRST byte is a type tag; payload length is fixed per type. We branch on the
// tag (more robust than branching on size) and pull known offsets.
//
//   tag 0x00 (18B): gear    -> byte[5]=current gear, byte[6]=max gear
//   tag 0x02 (10B): mode    -> byte[1]=assist mode, byte[2..3]=speed/10,
//                              byte[4]=assist level, byte[5]=cadence
//   tag 0x05 (13B): rider profile name (ASCII from byte 3)
//   tags 0x01/0x03/0x04/0x06: not decoded (recorded raw for diagnostics only)
//
// -1 (or -1.0) means "not yet received" so the UI can show a placeholder
// instead of a stale/fake value.
class StepsData {

    public var gear        as Number = -1;
    public var maxGear     as Number = -1;
    public var assistMode  as Number = -1;
    public var speed       as Float  = -1.0;   // km/h or mph tenths — units TBD on-device
    public var cadence     as Number = -1;
    public var assistLevel as Number = -1;
    public var battery     as Number = -1;     // %, from GATT battery service
    public var profileName as String? = null;

    // tag (Number) => raw byte-array copy of the last packet of that type.
    // Bounded at one entry per known tag, so this stays tiny.
    public var lastPackets as Dictionary = {};

    function initialize() {
    }

    // Parse one raw notification payload from the mode/gear characteristic.
    function onPacket(value as ByteArray?) as Void {
        if (value == null || value.size() == 0) {
            return;
        }
        var tag = value[0];
        lastPackets[tag] = value.slice(0, value.size());   // keep a copy for TEST view

        if (tag == 0x00 && value.size() >= 7) {
            gear    = value[5];
            maxGear = value[6];
        } else if (tag == 0x02 && value.size() >= 6) {
            assistMode  = value[1];
            speed       = (((value[3] << 8) | value[2]).toFloat()) / 10.0;
            assistLevel = value[4];
            cadence     = value[5];
        } else if (tag == 0x05 && value.size() > 3) {
            profileName = asciiZ(value, 3);
        }
    }

    // Clear live values on disconnect so the UI stops showing the last-known
    // gear as if it were current. Battery/profile are left as last-known.
    function onDisconnect() as Void {
        gear        = -1;
        maxGear     = -1;
        assistMode  = -1;
        speed       = -1.0;
        cadence     = -1;
        assistLevel = -1;
    }

    function hasGear() as Boolean {
        return gear > 0 && maxGear > 0;
    }

    // Build "AA BB CC" hex for a stored raw packet, or "" if none seen yet.
    function hexFor(tag as Number) as String {
        var v = lastPackets[tag];
        if (v == null) {
            return "";
        }
        try {
            return StringUtil.convertEncodedString(v, {
                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                :toRepresentation   => StringUtil.REPRESENTATION_STRING_HEX
            }).toUpper();
        } catch (e) {
            return "?";
        }
    }

    // Decode a NUL-terminated ASCII run starting at `start`.
    private function asciiZ(value as ByteArray, start as Number) as String {
        var s = "";
        for (var i = start; i < value.size(); i++) {
            var b = value[i];
            if (b == 0x00) {
                break;
            }
            if (b >= 0x20 && b < 0x7F) {
                s += (b.toChar()).toString();
            }
        }
        return s;
    }
}
