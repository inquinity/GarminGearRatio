using Toybox.BluetoothLowEnergy as Ble;
import Toybox.Application.Properties;
import Toybox.Lang;
import Toybox.StringUtil;

// BLE central for the Shimano SC-EM800 STEPS head unit.
//
// State machine (scan -> pair -> identify by MAC -> subscribe -> notify) is
// ported from markdotai/emtb's emtbDelegate.mc, which is proven against this
// exact 0x18EF service / 2AC1 characteristic on E7000/EN100 hardware. Adapted
// to feed StepsData and to enable notifications on 2AC1, whose payloads are
// then decoded by StepsData.onPacket().
//
// Connect IQ allows at most 3 registered BLE profiles; we use exactly 3:
// battery, mode/gear (notify), and the MAC-address read used to identify a bike.
class ShimanoBleDelegate extends Ble.BleDelegate {

    enum {
        STATE_INIT,
        STATE_CONNECTING,
        STATE_IDLE,
        STATE_DISCONNECTED
    }

    private var _data as StepsData;

    public  var state as Number = STATE_INIT;
    public  var connectedMACArray as ByteArray? = null;

    // Settings (pushed by the view): only ever bond to this bike when locked.
    public  var lastLock as Boolean = false;
    public  var lastMACArray as ByteArray? = null;

    private var currentScanning as Boolean = false;
    private var wantScanning as Boolean = false;

    // ── Shimano UUIDs (see SCEM800-BLE-protocol.md) ───────────────────────────
    // SC-EM800 advertises the 0x18FF service; we filter scan results on it.
    private var advertisedServiceUuid    = Ble.stringToUuid("000018ff-5348-494d-414e-4f5f424c4500");
    private var modeServiceUuid          = Ble.stringToUuid("000018ef-5348-494d-414e-4f5f424c4500");
    private var modeCharacteristicUuid   = Ble.stringToUuid("00002ac1-5348-494d-414e-4f5f424c4500");
    private var batteryServiceUuid       = Ble.stringToUuid("0000180f-0000-1000-8000-00805f9b34fb");
    private var batteryCharacteristicUuid= Ble.stringToUuid("00002a19-0000-1000-8000-00805f9b34fb");
    private var macServiceUuid           = Ble.stringToUuid("000018fe-1212-efde-1523-785feabcd123");
    private var macCharacteristicUuid    = Ble.stringToUuid("00002ae3-1212-efde-1523-785feabcd123");

    private var profileRegisterSuccessCount as Number = 0;

    // MAC-read handshake state
    private var readMACScanResult as Ble.ScanResult? = null;
    private var readMACCounter as Number = 0;
    private const readMACCounterMaxAllowed = 5;

    // battery / notify request flags
    private var wantReadBattery as Boolean = false;
    private var waitingRead as Boolean = false;
    private var wantNotifyMode as Boolean = false;
    private var writingNotifyMode as Boolean = false;
    private var currentNotifyMode as Boolean = false;
    private var waitingWrite as Boolean = false;

    // devices already tested and rejected, so we don't retry them forever
    private var scannedList as Array<Ble.ScanResult> = [];
    private const maxScannedListSize = 10;

    function initialize(data as StepsData) {
        _data = data;
        BleDelegate.initialize();
        bleInitProfiles();
        startConnecting();
    }

    // ── Public API used by the view ───────────────────────────────────────────

    function isRegistered() as Boolean { return profileRegisterSuccessCount >= 3; }
    function isConnecting() as Boolean { return state == STATE_CONNECTING; }
    function isConnected()  as Boolean { return state == STATE_IDLE; }

    function requestReadBattery() as Void { wantReadBattery = true; }
    function requestNotifyMode(wantMode as Boolean) as Void { wantNotifyMode = wantMode; }

    // Pushed from the view when settings change.
    function setLock(lock as Boolean, macArray as ByteArray?) as Void {
        lastLock = lock;
        lastMACArray = macArray;
    }

    function startConnecting() as Void {
        _data.onDisconnect();
        state = STATE_CONNECTING;
        connectedMACArray = null;
        wantScanning = true;
        readMACScanResult = null;
        deleteScannedList();
        writingNotifyMode = false;
        currentNotifyMode = false;
    }

    // Called once per second from the view's compute(). Drives scan/connect and
    // issues battery reads / notify writes when idle.
    function compute() as Void {
        if (wantScanning != currentScanning) {
            Ble.setScanState(wantScanning ? Ble.SCAN_STATE_SCANNING : Ble.SCAN_STATE_OFF);
        }

        switch (state) {
            case STATE_CONNECTING:
                break;  // waiting on onScanResults()

            case STATE_IDLE: {
                var d = pairedDevice();
                if (d == null || !d.isConnected()) {
                    bleDisconnect();
                    _data.onDisconnect();
                    state = STATE_DISCONNECTED;
                } else if (!waitingRead && !waitingWrite) {
                    if (wantReadBattery) {
                        if (bleReadBattery()) {
                            wantReadBattery = false;
                            waitingRead = true;
                        } else {
                            _data.battery = -1;
                        }
                    } else if (wantNotifyMode != currentNotifyMode) {
                        writingNotifyMode = wantNotifyMode;
                        if (bleWriteNotifications(writingNotifyMode)) {
                            waitingWrite = true;
                        }
                    }
                }
                break;
            }

            case STATE_DISCONNECTED:
                startConnecting();
                break;
        }
    }

    // ── Profile registration ──────────────────────────────────────────────────

    private function bleInitProfiles() as Void {
        var batteryProfile = {
            :uuid => batteryServiceUuid,
            :characteristics => [ { :uuid => batteryCharacteristicUuid } ]
        };
        var modeProfile = {
            :uuid => modeServiceUuid,
            :characteristics => [
                { :uuid => modeCharacteristicUuid, :descriptors => [Ble.cccdUuid()] }
            ]
        };
        var macProfile = {
            :uuid => macServiceUuid,
            :characteristics => [ { :uuid => macCharacteristicUuid } ]
        };
        try {
            Ble.registerProfile(batteryProfile);
            Ble.registerProfile(modeProfile);
            Ble.registerProfile(macProfile);
        } catch (e) {
            // registration cap exceeded or unsupported — isRegistered() stays false
        }
    }

    function onProfileRegister(uuid, status) as Void {
        if (status == Ble.STATUS_SUCCESS) {
            profileRegisterSuccessCount += 1;
        }
    }

    // ── Scanning / pairing ────────────────────────────────────────────────────

    function onScanStateChange(scanState, status) as Void {
        currentScanning = (scanState == Ble.SCAN_STATE_SCANNING);
        readMACScanResult = null;
        deleteScannedList();
    }

    function onScanResults(scanResults) as Void {
        if (!wantScanning) {
            return;
        }

        var newList = [] as Array<Ble.ScanResult>;
        for (;;) {
            var r = scanResults.next() as Ble.ScanResult?;
            if (r == null) {
                break;
            }
            if (iterContains(r.getServiceUuids(), advertisedServiceUuid)) {
                var isNew = true;
                for (var i = 0; i < scannedList.size(); i++) {
                    if (r.isSameDevice(scannedList[i])) {
                        scannedList[i] = r;
                        isNew = false;
                        break;
                    }
                }
                if (isNew) {
                    newList.add(r);
                }
            }
        }

        if (readMACScanResult == null && newList.size() > 0) {
            // pick the strongest-signal candidate
            var bestI = 0;
            var bestRssi = newList[0].getRssi();
            for (var i = 1; i < newList.size(); i++) {
                var rssi = newList[i].getRssi();
                if (rssi > bestRssi) {
                    bestI = i;
                    bestRssi = rssi;
                }
            }
            readMACScanResult = newList[bestI];
            readMACCounter = 0;
            var d = Ble.pairDevice(readMACScanResult);
            if (d != null) {
                if (d.isConnected()) {
                    startReadingMAC();  // onConnectedStateChanged isn't always fired
                }
            } else {
                readMACScanResult = null;
            }
        }
    }

    function onConnectedStateChanged(device, connectionState) as Void {
        if (connectionState == Ble.CONNECTION_STATE_CONNECTED) {
            startReadingMAC();
        }
    }

    // ── MAC identification ────────────────────────────────────────────────────

    private function startReadingMAC() as Void {
        if (readMACScanResult != null) {
            if (readMACCounter < readMACCounterMaxAllowed) {
                if (bleReadMAC()) {
                    readMACCounter += 1;
                } else {
                    readMACScanResult = null;
                }
            } else {
                readMACScanResult = null;
            }
        }
    }

    private function completeReadMAC(readMACArray as ByteArray) as Void {
        if (readMACScanResult == null) {
            return;
        }
        var matches = (!lastLock || lastMACArray == null || sameMACArray(lastMACArray, readMACArray));
        if (matches) {
            saveLastMAC(readMACArray);
            wantScanning = false;
            Ble.setScanState(Ble.SCAN_STATE_OFF);
            state = STATE_IDLE;
            connectedMACArray = readMACArray;
        } else {
            failedReadMACScan();  // not the locked bike
        }
    }

    private function failedReadMACScan() as Void {
        if (readMACScanResult != null) {
            addToScannedList(readMACScanResult);
            readMACScanResult = null;
            bleDisconnect();
        }
    }

    // ── BLE reads / writes ────────────────────────────────────────────────────

    function bleDisconnect() as Void {
        var d = pairedDevice();
        if (d != null) {
            Ble.unpairDevice(d);
        }
    }

    private function bleWriteNotifications(wantOn as Boolean) as Boolean {
        var d = pairedDevice();
        if (d != null && d.isConnected()) {
            try {
                var ds = d.getService(modeServiceUuid);
                if (ds != null) {
                    var dsc = ds.getCharacteristic(modeCharacteristicUuid);
                    if (dsc != null) {
                        var cccd = dsc.getDescriptor(Ble.cccdUuid());
                        cccd.requestWrite([(wantOn ? 0x01 : 0x00), 0x00]b);
                        return true;
                    }
                }
            } catch (e) {
            }
        }
        return false;
    }

    private function bleReadBattery() as Boolean {
        var d = pairedDevice();
        if (d != null && d.isConnected()) {
            try {
                var ds = d.getService(batteryServiceUuid);
                if (ds != null) {
                    var dsc = ds.getCharacteristic(batteryCharacteristicUuid);
                    if (dsc != null) {
                        dsc.requestRead();
                        return true;
                    }
                }
            } catch (e) {
            }
        }
        return false;
    }

    private function bleReadMAC() as Boolean {
        var d = pairedDevice();
        if (d != null && d.isConnected()) {
            try {
                var ds = d.getService(macServiceUuid);
                if (ds != null) {
                    var dsc = ds.getCharacteristic(macCharacteristicUuid);
                    if (dsc != null) {
                        dsc.requestRead();
                        return true;
                    }
                }
            } catch (e) {
            }
        }
        return false;
    }

    function onCharacteristicRead(characteristic, status, value) as Void {
        if (characteristic.getUuid().equals(batteryCharacteristicUuid)) {
            if (value != null && value.size() > 0) {
                _data.battery = value[0].toNumber();
            }
        } else if (characteristic.getUuid().equals(macCharacteristicUuid)) {
            if (status == Ble.STATUS_SUCCESS && value != null && value.size() > 0) {
                completeReadMAC(value.reverse());  // reverse to match phone-reported MAC order
            } else {
                startReadingMAC();  // retry
            }
        }
        waitingRead = false;
    }

    function onDescriptorWrite(descriptor, status) as Void {
        var cd = descriptor.getCharacteristic();
        if (cd != null && cd.getUuid().equals(modeCharacteristicUuid)) {
            if (status == Ble.STATUS_SUCCESS) {
                currentNotifyMode = writingNotifyMode;
            }
        }
        waitingWrite = false;
    }

    // Every 2AC1 notification lands here; hand the raw payload to StepsData.
    function onCharacteristicChanged(characteristic, value) as Void {
        if (characteristic.getUuid().equals(modeCharacteristicUuid)) {
            _data.onPacket(value);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // We only ever connect to one bike; the paired iterator has at most one.
    private function pairedDevice() as Ble.Device? {
        return Ble.getPairedDevices().next() as Ble.Device?;
    }

    function sameMACArray(a as ByteArray?, b as ByteArray?) as Boolean {
        if (a == null || b == null || a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    private function saveLastMAC(newMACArray as ByteArray?) as Void {
        if (newMACArray == null) {
            return;
        }
        lastMACArray = newMACArray;
        try {
            var s = StringUtil.convertEncodedString(newMACArray, {
                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                :toRepresentation   => StringUtil.REPRESENTATION_STRING_HEX
            });
            Properties.setValue("LastMAC", s.toUpper());
        } catch (e) {
        }
    }

    private function iterContains(iter, obj) as Boolean {
        for (var uuid = iter.next(); uuid != null; uuid = iter.next()) {
            if (uuid.equals(obj)) {
                return true;
            }
        }
        return false;
    }

    function addToScannedList(r) as Void {
        if (scannedList.size() >= maxScannedListSize) {
            scannedList = scannedList.slice(1, maxScannedListSize);
        }
        scannedList.add(r);
    }

    function deleteScannedList() as Void {
        scannedList = new [0];
    }
}
