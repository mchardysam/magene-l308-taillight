import Toybox.Lang;
import Toybox.BluetoothLowEnergy;
import Toybox.System;

//! Trimmed BLE link for the data field: scan L308_* -> connect -> notify -> handshake ->
//! list (count) -> read battery -> ready. Then selectSlot() writes ONLY when the target
//! changes (no polling). Reconnects if the link drops. Only ever writes 8ce5cc05.
class BleLink extends BluetoothLowEnergy.BleDelegate {

    enum { ST_IDLE, ST_SCANNING, ST_CONNECTING, ST_READY, ST_ERROR }

    public var state as Number = ST_IDLE;
    public var patternCount as Number = 0;
    public var battLevel as Number = -1;        // 0-100, -1 = unknown

    // Standard Battery Service / Level characteristic (read-only here).
    private const BATT_SVC = "0000180f-0000-1000-8000-00805f9b34fb";
    private const BATT_CHR = "00002a19-0000-1000-8000-00805f9b34fb";

    private var _started as Boolean = false;
    private var _profilesLeft as Number = 0;
    private var _cmd as BluetoothLowEnergy.Characteristic? = null;
    private var _batt as BluetoothLowEnergy.Characteristic? = null;
    private var _phase as Symbol = :idle;
    private var _pending as Boolean = false;
    private var _lastCommanded as Number = -1;
    private var _wantSlot as Number = -1;

    public function initialize() {
        BleDelegate.initialize();
    }

    public function isReady() as Boolean { return state == ST_READY; }

    // Debug/simulator only: BLE isn't real in the sim, so fake a connected light to preview
    // the "connected" layout. The (:debug) annotation excludes this from release/store builds.
    (:debug)
    public function previewConnected(count as Number, batt as Number) as Void {
        state = ST_READY;
        patternCount = count;
        battLevel = batt;
    }

    // Called from compute(): start the connection flow once.
    public function ensureStarted() as Void {
        if (_started) { return; }
        _started = true;
        BluetoothLowEnergy.setDelegate(self);
        _profilesLeft = 2;
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => Protocol.serviceUuid(),
                :characteristics => [
                    { :uuid => Protocol.cmdUuid(), :descriptors => [ BluetoothLowEnergy.cccdUuid() ] }
                ]
            });
            BluetoothLowEnergy.registerProfile({
                :uuid => BluetoothLowEnergy.stringToUuid(BATT_SVC),
                :characteristics => [ { :uuid => BluetoothLowEnergy.stringToUuid(BATT_CHR) } ]
            });
        } catch (e) {
            state = ST_ERROR;
        }
    }

    // Request a target slot (0-based). Writes only when it actually changes.
    public function selectSlot(slot as Number) as Void {
        _wantSlot = slot;
        if (state == ST_READY && slot != _lastCommanded && !_pending) {
            doSelect(slot);
        }
    }

    private function doSelect(slot as Number) as Void {
        var ch = _cmd;
        if (ch == null) { return; }
        _phase = :select;
        _pending = true;
        _lastCommanded = slot;
        ch.requestWrite(Protocol.selectCmd(slot), { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT });
    }

    private function flush() as Void {
        if (state == ST_READY && _wantSlot >= 0 && _wantSlot != _lastCommanded && !_pending) {
            doSelect(_wantSlot);
        }
    }

    // ---- BleDelegate callbacks ----

    public function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        _profilesLeft -= 1;
        if (_profilesLeft <= 0) {
            state = ST_SCANNING;
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        }
    }

    public function onScanResults(results as BluetoothLowEnergy.Iterator) as Void {
        var r = results.next();
        while (r != null) {
            var sr = r as BluetoothLowEnergy.ScanResult;
            var name = sr.getDeviceName();
            if (name != null && name.find(Protocol.NAME_PREFIX) == 0) {
                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
                state = ST_CONNECTING;
                BluetoothLowEnergy.pairDevice(sr);
                return;
            }
            r = results.next();
        }
    }

    public function onConnectedStateChanged(device as BluetoothLowEnergy.Device, connectionState as BluetoothLowEnergy.ConnectionState) as Void {
        if (connectionState == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            var svc = device.getService(Protocol.serviceUuid());
            _cmd = (svc == null) ? null : svc.getCharacteristic(Protocol.cmdUuid());
            var bsvc = device.getService(BluetoothLowEnergy.stringToUuid(BATT_SVC));
            _batt = (bsvc == null) ? null : bsvc.getCharacteristic(BluetoothLowEnergy.stringToUuid(BATT_CHR));
            var ch = _cmd;
            if (ch == null) { state = ST_ERROR; return; }
            var cccd = ch.getDescriptor(BluetoothLowEnergy.cccdUuid());
            if (cccd != null) {
                _pending = true;
                _phase = :cmdcccd;
                cccd.requestWrite([0x01, 0x00]b);
            } else {
                sendHandshake();
            }
        } else if (connectionState == BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED) {
            state = ST_SCANNING;
            _cmd = null;
            _batt = null;
            _phase = :idle;
            _pending = false;
            _lastCommanded = -1;
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        }
    }

    public function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, status as BluetoothLowEnergy.Status) as Void {
        _pending = false;
        sendHandshake();
    }

    private function sendHandshake() as Void {
        var ch = _cmd;
        if (ch == null) { return; }
        _phase = :handshake;
        _pending = true;
        ch.requestWrite(Protocol.handshake(), { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT });
    }

    public function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        _pending = false;
        if (_phase == :handshake) {
            _phase = :list;
            _pending = true;
            characteristic.requestWrite(Protocol.listCmd(), { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT });
        } else if (_phase == :list) {
            _phase = :idle;
            readBattery();
        } else {
            _phase = :idle;
            flush();
        }
    }

    private function readBattery() as Void {
        var b = _batt;
        if (b != null) {
            _pending = true;
            _phase = :battread;
            b.requestRead();
        }
    }

    public function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status, value as ByteArray) as Void {
        _pending = false;
        _phase = :idle;
        if (status == BluetoothLowEnergy.STATUS_SUCCESS && value.size() >= 1) {
            battLevel = value[0];
        }
        flush();
    }

    public function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as ByteArray) as Void {
        var count = Protocol.parseListCount(value);
        if (count != null) {
            patternCount = count;
            state = ST_READY;
            flush();
        }
    }
}
