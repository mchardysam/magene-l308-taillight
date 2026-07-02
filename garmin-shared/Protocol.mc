import Toybox.Lang;
import Toybox.BluetoothLowEnergy;

//! Magene L308 vendor BLE protocol — exact bytes, mirrored from l308_send.py.
//!
//! SAFETY: only the vendor control service/characteristic below are ever used.
//! The SMP/firmware service 8d53dc1d-... / char da2e7828-... is NEVER referenced
//! here or anywhere else (writing it can brick the light).
module Protocol {

    // Vendor control service + command characteristic (write-w/o-response + notify).
    const SERVICE_STR = "8ce5cc01-0a4d-11e9-ab14-d663bd873d93";
    const CMD_STR     = "8ce5cc05-0a4d-11e9-ab14-d663bd873d93";

    // Advertised name prefix to match while scanning, e.g. "L308_1A2B".
    const NAME_PREFIX = "L308_";

    // UUIDs must be built at runtime (stringToUuid isn't a compile-time constant).
    function serviceUuid() as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid(SERVICE_STR);
    }

    function cmdUuid() as BluetoothLowEnergy.Uuid {
        return BluetoothLowEnergy.stringToUuid(CMD_STR);
    }

    // Opening handshake the app sends first (optional but harmless).
    //   80 F1 01 01 00 00 00 00 00 00 00 00 00  -> reply 94 F5 01 01 ...
    function handshake() as ByteArray {
        return [0x80, 0xF1, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]b;
    }

    // List patterns (to learn the stored count).
    //   94 F1 23 E2 01  -> reply 94 F5 23 E2 01 <count> ?? <id x4 LE> ...
    function listCmd() as ByteArray {
        return [0x94, 0xF1, 0x23, 0xE2, 0x01]b;
    }

    // Select pattern slot N (0-based). 94 F2 23 E1 01 01 <N> 00 00 00 -> echo 94 F5 23 E1 ...
    function selectCmd(index as Number) as ByteArray {
        return [0x94, 0xF2, 0x23, 0xE1, 0x01, 0x01, (index & 0xFF), 0x00, 0x00, 0x00]b;
    }

    // Parse a pattern-list notification: 94 F5 23 E2 01 <count> <current_index> <id x4 LE>...
    // Returns the pattern count, or null if this isn't a list reply.
    function parseListCount(value as ByteArray) as Number? {
        if (value.size() >= 6 && value[2] == 0x23 && value[3] == 0xE2) {
            return value[5];
        }
        return null;
    }

    // Currently-selected pattern index, reported in the list reply at offset 6 (the byte
    // right after the count). Confirmed across capture sessions: e.g. after selecting slot
    // 4, the list reply reads "...01 0a 04...". The light only reports it in THIS reply —
    // there is no unsolicited "pattern changed" notification — so re-query to resync.
    function parseCurrentIndex(value as ByteArray) as Number? {
        if (value.size() >= 7 && value[2] == 0x23 && value[3] == 0xE2) {
            return value[6];
        }
        return null;
    }

    // True if this notification is the select-echo (94 F5 23 E1 ...).
    function isSelectEcho(value as ByteArray) as Boolean {
        return value.size() >= 4 && value[2] == 0x23 && value[3] == 0xE1;
    }
}
