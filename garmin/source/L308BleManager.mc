import Toybox.Lang;
import Toybox.BluetoothLowEnergy;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Application;

//! Reusable BLE core: scan -> connect -> enable notify -> handshake -> list,
//! then prev()/next() send the L308 "select pattern" command for currentIndex -/+ 1
//! (wrapped). Shared unchanged by both the device-app and (later) the widget shell.
//!
//! Connect IQ allows only ONE outstanding GATT operation at a time, so every step is
//! chained through its completion callback (onDescriptorWrite / onCharacteristicWrite).
class L308BleManager extends BluetoothLowEnergy.BleDelegate {

    // UI-facing status.
    enum {
        STATUS_INIT,
        STATUS_SCANNING,
        STATUS_CONNECTING,
        STATUS_READY,
        STATUS_ERROR
    }

    public var status as Number = STATUS_INIT;
    public var statusText as String = "Starting...";
    public var patternCount as Number = 0;
    public var currentIndex as Number = 0;   // seeded from the list reply (byte 6), then tracked optimistically
    public var lastAction as String = "";

    private var _device as BluetoothLowEnergy.Device? = null;
    private var _cmdChar as BluetoothLowEnergy.Characteristic? = null;
    private var _ready as Boolean = false;
    private var _pending as Boolean = false;  // a GATT op is in flight
    private var _queued as Boolean = false;   // a press arrived while pending -> resend latest
    private var _phase as Symbol = :idle;     // :handshake | :list | :select | :idle

    public function initialize() {
        BleDelegate.initialize();
        BluetoothLowEnergy.setDelegate(self);
        registerProfileAndScan();
    }

    public function close() as Void {
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        } catch (e) {}
        if (_device != null) {
            try {
                BluetoothLowEnergy.unpairDevice(_device);
            } catch (e) {}
        }
    }

    // ---- public input API ----

    public function next() as Void { changeBy(1); }
    public function prev() as Void { changeBy(-1); }

    public function isReady() as Boolean { return _ready; }

    // Re-query the list to resync count + current index. The light has no live "pattern
    // changed" push, so if it's changed on the light directly (or you reconnect), call this
    // to catch up. Safe no-op if disconnected or a write is already in flight.
    public function refresh() as Void {
        var ch = _cmdChar;
        if (ch == null || _pending) { return; }
        _phase = :list;
        _pending = true;
        ch.requestWrite(
            Protocol.listCmd(),
            { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT }
        );
    }

    private function changeBy(delta as Number) as Void {
        if (!_ready || patternCount <= 0 || _cmdChar == null) {
            return;
        }
        // Always reflect the user's intent immediately; the light follows when free.
        currentIndex = ((currentIndex + delta) % patternCount + patternCount) % patternCount;
        lastAction = "-> pattern " + (currentIndex + 1);
        WatchUi.requestUpdate();
        saveState();
        if (_pending) {
            _queued = true;   // coalesce rapid presses to the latest index
            return;
        }
        sendSelect(currentIndex);
    }

    private function sendSelect(idx as Number) as Void {
        if (_cmdChar == null) { return; }
        _phase = :select;
        _pending = true;
        // write-without-response, exactly like the app (wt=1).
        _cmdChar.requestWrite(
            Protocol.selectCmd(idx),
            { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT }
        );
    }

    // ---- setup ----

    private function registerProfileAndScan() as Void {
        var profile = {
            :uuid => Protocol.serviceUuid(),
            :characteristics => [
                {
                    :uuid => Protocol.cmdUuid(),
                    :descriptors => [ BluetoothLowEnergy.cccdUuid() ]
                }
            ]
        };
        try {
            BluetoothLowEnergy.registerProfile(profile);
        } catch (e) {
            setStatus(STATUS_ERROR, "Profile failed");
        }
    }

    private function sendHandshake() as Void {
        if (_cmdChar == null) { return; }
        _phase = :handshake;
        _pending = true;
        _cmdChar.requestWrite(
            Protocol.handshake(),
            { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT }
        );
    }

    private function setStatus(s as Number, text as String) as Void {
        status = s;
        statusText = text;
        WatchUi.requestUpdate();
    }

    // Persist last-known state so the glance tile can show it without a connection.
    private function saveState() as Void {
        Application.Storage.setValue("count", patternCount);
        Application.Storage.setValue("index", currentIndex);
    }

    // ---- BleDelegate callbacks ----

    public function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, regStatus as BluetoothLowEnergy.Status) as Void {
        setStatus(STATUS_SCANNING, "Scanning...");
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    public function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
        var result = scanResults.next();
        while (result != null) {
            var sr = result as BluetoothLowEnergy.ScanResult;
            var name = sr.getDeviceName();
            if (name != null && name.find(Protocol.NAME_PREFIX) == 0) {
                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
                setStatus(STATUS_CONNECTING, "Connecting...");
                _device = BluetoothLowEnergy.pairDevice(sr);
                return;
            }
            result = scanResults.next();
        }
    }

    public function onConnectedStateChanged(device as BluetoothLowEnergy.Device, connectionState as BluetoothLowEnergy.ConnectionState) as Void {
        if (connectionState == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            _device = device;
            var service = device.getService(Protocol.serviceUuid());
            if (service == null) {
                setStatus(STATUS_ERROR, "No service");
                return;
            }
            _cmdChar = service.getCharacteristic(Protocol.cmdUuid());
            if (_cmdChar == null) {
                setStatus(STATUS_ERROR, "No char");
                return;
            }
            // Enable notifications by writing the CCCD = 01 00, then handshake (onDescriptorWrite).
            var cccd = _cmdChar.getDescriptor(BluetoothLowEnergy.cccdUuid());
            if (cccd != null) {
                _pending = true;
                cccd.requestWrite([0x01, 0x00]b);
            } else {
                sendHandshake();
            }
        } else if (connectionState == BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED) {
            _ready = false;
            _cmdChar = null;
            _phase = :idle;
            _pending = false;
            setStatus(STATUS_SCANNING, "Reconnecting...");
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        }
    }

    public function onDescriptorWrite(descriptor as BluetoothLowEnergy.Descriptor, writeStatus as BluetoothLowEnergy.Status) as Void {
        _pending = false;
        sendHandshake();   // notifications enabled -> opening handshake
    }

    public function onCharacteristicWrite(characteristic as BluetoothLowEnergy.Characteristic, writeStatus as BluetoothLowEnergy.Status) as Void {
        _pending = false;
        if (_phase == :handshake) {
            // handshake sent -> ask for the pattern list (reuse the non-null char we just wrote)
            _phase = :list;
            _pending = true;
            characteristic.requestWrite(
                Protocol.listCmd(),
                { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT }
            );
        } else if (_phase == :list) {
            _phase = :idle;   // count arrives via onCharacteristicChanged
        } else {
            _phase = :idle;
            if (_queued) {
                _queued = false;
                sendSelect(currentIndex);   // resend the latest coalesced index
            }
        }
    }

    public function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic, value as ByteArray) as Void {
        var count = Protocol.parseListCount(value);
        if (count != null) {
            patternCount = count;
            // Seed from the light's actual current pattern (list reply byte 6), like the
            // C606 shows "mode X" on connect. Clamp in case the list shrank under it.
            var cur = Protocol.parseCurrentIndex(value);
            if (cur != null && cur >= 0 && cur < count) {
                currentIndex = cur;
            } else {
                currentIndex = 0;
            }
            _ready = true;
            lastAction = "On pattern " + (currentIndex + 1);
            setStatus(STATUS_READY, "Ready");
            saveState();
            return;
        }
        // select-echo and other replies are not needed for the MVP.
    }
}
