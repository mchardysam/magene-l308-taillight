# Magene L308 — BLE protocol & `light_mode.bin` spec

Unofficial, independent reference for the Magene **L308** smart taillight, for interop on
owned hardware. This is the dry source-of-truth spec that the clients (`web/`, `garmin/`)
implement; the project narrative/status lives in `README.md`.

Markers: ✅ confirmed on hardware · ⚠️ partially understood · ❓ unknown · 🚫 never touch.

Device: model `284` (`L308`), manufacturer `Magene` (id **107** / `0x6b`), firmware `0.120`.
Region (China `…01…` vs export `…04…`) is **not** enforced by the device — it's app/cloud-side.

---

## 1. GATT map ✅

| Service | Char (UUID short) | Props | Role |
|---|---|---|---|
| Device Info `180a` | Model `2a24` | read | `"284"` |
| | Manufacturer `2a29` | read | `"Magene"` |
| | Firmware `2a26` | read | `"0.120"` |
| Battery `180f` | Level `2a19` | read, notify | battery % |
| **Vendor `8ce5cc01-0a4d-11e9-ab14-d663bd873d93`** | **`8ce5cc05`** | write, write-no-resp, **notify** | **control channel — commands + replies** |
| | **`8ce5cc06`** | write, write-no-resp, notify | **bulk file upload** (chunks) |
| | `8ce5cc04` | read | status; reads `60 00 00 00` ❓ (meaning unknown) |
| Nordic UART `6e400001-…` | `6e400002` / `6e400003` | write-no-resp / notify | ❓ present but unused by the app for control |
| 🚫 **SMP `8d53dc1d-…`** | `da2e7828` | write-no-resp, notify | **mcumgr/MCUboot firmware mgmt — NEVER WRITE (brick risk)**. fs/shell groups are disabled. |

All control writes are **write-without-response**. Device replies arrive as **notifications**
on `8ce5cc05`. The device **never sends unsolicited notifications** — every reply follows a query. ✅

---

## 2. Framing ✅

```
94 <dir> <grp> <cmd> <payload…>
```
- `dir`: `f1` = query/get · `f2` = set · `f5` = device reply (notify).
- **Handshake** (first write after connect; uses `80`, not `94`):
  `80 f1 01 01 00 00 00 00 00 00 00 00 00`
  → reply `94 f5 01 01  14 0b 00  6b  00 01 01 14 01`
  - byte 7 `0x6b` = **107 = manufacturer id** ✅. The rest (`14 0b … 01 01 14 01`) is a **fixed
    L308 model signature** (not region- or serial-specific; ⚠️ exact field meanings unknown).

### Command summary

| Purpose                                                 | Query → Reply                                                                                    | Notes                                                                                                       |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Settings                                                | `94 f1 23 f0 01` → `94 f5 23 f0 01 [brake] [sleep] [to_lo] [to_hi] 01`                           | §3                                                                                                          |
| Set settings                                            | `94 f2 23 f0 01 [brake] [sleep] [to_lo] [to_hi] 01`                                              | §3                                                                                                          |
| Pattern list                                            | `94 f1 23 e2 01` → `94 f5 23 e2 01 [count] [cur_idx] [id×4 LE]…`                                 | §4                                                                                                          |
| Pattern select                                          | `94 f2 23 e1 01 01 [slot] 00 00 00` → echo `94 f5 23 e1 …`                                       | slot 0-based ✅                                                                                              |
| Upload file                                             | grp `01`, cmds `24/25/26`                                                                        | §5                                                                                                          |
| Device info reads                                       | `94 f1 01 {02,03,11,13}` → `94 f5 01 …`                                                          | `01 11`→{SKU code, mfr `6b`, spu `1c01`=284, "L308"}, `01 13`→ASCII serial, `01 02`→HW ids, `01 03`→zeros |
| Region read | `94 f1 10 f3 04` → `94 f5 10 f3 04 03 [region] ff ff ff ff` | ✅ byte 6 = device **region**: `1` export/intl, `2` China (matches cloud region codes). Self-reported only — not enforced on-device. |                                                                                                             |

---

## 3. Settings (`23 f0`) ✅

`94 f5/f2 23 f0 01 [brake] [sleep] [timeout LE16] 01`
- `brake`: `0/1`.
- `sleep`: **bit 0 = enabled**; **high nibble = sub-mode flags** (factory `0xf1`). ✅
  ⚠️ A plain set-settings write stores only `0x00/0x01`, **clearing the high nibble** — OR it
  back (`0xf0 | enable`) to preserve the factory sub-mode. Individual sub-mode bit meanings unknown.
- `timeout` (LE16): auto-sleep seconds (e.g. `2c01`=300, `3c00`=60, `7800`=120).

---

## 4. Pattern list (`23 e2`) ✅

`94 f5 23 e2 01 [count] [cur_idx] [id ×4 LE]…`
- `count` = number of stored patterns.
- `cur_idx` = **current selected slot** (0-based) — tracks selection independently of count
  (e.g. `08 00` after a fresh upload, `06 03` after a restore). ✅
- This is the **only** read the device offers — there is **no read-back of pattern content**.
  Keep a local copy of the store (the device can't report its contents).

---

## 5. File upload (whole store, every change)

The app never uploads a single pattern — it re-sends the entire `light_mode.bin` store.
Sequence (start/header on `8ce5cc05`, chunks on `8ce5cc06`):

| Step | Frame |
|---|---|
| start | `94 f2 01 24 01 00 00 00 00 01 00 [ts LE32] 00×6` (carries unix ts) |
| header | `94 f2 01 25 0b 00×6 [size LE32] [nchunks LE16] [crc16 LE16] 00×4 "light_mode.bin"` |
| chunk × N | `94 f2 01 26 [idx LE16, 1-based] [len LE16] [data]` — ~236 B each, on `8ce5cc06` |
| commit | `94 f2 01 24 02 00 00 00 00 01 02 [ts LE32] 00×6` |

- **checksum** = CRC16/XMODEM (poly `0x1021`, init `0x0000`) over the whole file. ✅
- Device acks start/header/commit via `94 f5 …` notifications.

---

## 6. `light_mode.bin` format ✅

`[5-byte file header] + N × [186-byte record]`,  `size = 5 + N*186`.

**File header:** `00 01 [count] [b3] 00`
- `b3` = `0x04` from the app, `0x00` from the cloud download — ⚠️ **the device ignores byte 3** (both accepted).

**Record (fixed 186 bytes):**

| offset | field |
|---|---|
| 0–3 | pattern id (LE32) |
| 4 | type: `01`=solid · `02`=gif · `03`=flashing/pulsing · `04`=text |
| 5 | solid/timed = `01`; gif = frame count; text = char count |
| 6–10 | type-specific (see §7) |
| 11– | **1-bit-per-LED bitmap** (13 bytes = 100 bits). LED = `row*10 + col`; corners `0,9,90,99` unused → **96 LEDs**. ✅ |
| tail | zero padding (or more frames for gif/text) |

---

## 7. Record types & per-type fields ✅

**Solid (`01 01`)** — `[id] 01 01 [bright] ff 00 00 00 [bitmap@11]`
- offset 6 `bright`: **proportional, higher = brighter** (`byte ≈ 0.175·pct`): `0x04`≈20 %,
  `0x06`≈35 %, `0x12` = app's 100 %, `0x01`≈off. Hardware keeps brightening above `0x12`
  (headroom past the app's max). ✅ swept.
- offset 7 = `ff` flag. offsets 8–10 = `00` (unused for solid).

**Flashing / Pulsing (`03 01 18`)** — `[id] 03 01 18 [b7] [b7dup] [max%] [min%] [bitmap@11]`
- offset 7 `b7` = `[bit7 mode] | [rate low-bits]`: **bit7 (`0x80`)** → 0 = Flashing, 1 = Pulsing. ✅
  - Flashing rate: higher = slower, interval ≈ `sec+4` (`0x06`→2 s, `0x08`→4 s). ✅
  - Pulsing rate: higher = slower, period ≈ `4 + lowbits/12` s (`0x00`→4 s, `0x30`→8 s). ⚠️ formula
    is an estimate from 2 cloud points + 1 sweep.
- offset 8 = duplicate of offset 7.
- offsets 9 / 10 = **max % / min %** brightness — direct (`50 14` = 80/20). ✅

**GIF / animation (`02`)** — `[id] 02 [count]` then per frame (18 B from `6 + i*18`):
`18 [fps] 00 00 00 [13-byte bitmap]`.
- ⚠️ **No brightness field.** The `00 00 00` bytes are never set (across 24 real gifs) and setting
  them has **no hardware effect** (✅ tested). Animations run at **fixed full brightness — cannot be dimmed.**

**Scrolling text (`04`)** — `[id] 04 [char count]`, then per-char glyph frames in the same
18-byte block layout; offset 7 = scroll speed. ⚠️ **No brightness field** either (full-on).

> **Dimming summary:** only **Solid** (offset 6) and **Flashing/Pulsing** (offsets 9/10) can be
> dimmed. **GIF and text are always full brightness** — there is no per-record, global, or
> inherited-from-preceding-pattern way to dim them (all three exhausted on hardware).

---

## 8. Open questions / suspected no-ops ❓

- **Handshake descriptor bytes** (`14 0b 00 … 01 01 14 01`, beyond byte 7 = mfr id) — a fixed
  L308 model signature (not region/serial-specific); ⚠️ exact field meanings still unknown
  (likely hw/protocol version ids).
- **`94 f1 10 f3` group** — ✅ arg `04` = **device region** (`1`=export/intl, `2`=China). arg `05`
  → all-zero config flag (same on both units; likely an unset feature/store flag). args 0–3, 6–8
  don't respond. Write side (`f2`) not probed.
- **Device-info reads** — ✅ mostly resolved: `01 11` = model {SKU config-code (export `0x80`,
  China `0x01`), mfr `0x6b`, spu `0x011c`=284, "L308"}; `01 13` = full ASCII serial; `01 02` = HW
  ids ("L020100050" PCBA/model + a per-unit mfg code sharing the serial's batch prefix);
  `01 03` = all zeros (empty/unused).
- **`8ce5cc04` status char** — reads a constant `60 00 00 00` (same on both units, not state-varying
  in tests); ❓ meaning unknown. **Nordic UART** service present but unused by the app for control.
- **Sleep sub-mode bits** (high nibble `0xf0`) — confirmed to exist; individual bit meanings unknown.
- **File-header byte 3** (`0x04` vs `0x00`) — **no-op** (device ignores it).
- **Solid record bytes 8–10** — always `00`; **no-op** for solids (only used by the timed type).

---

## 9. Safety ✅

- Replay only captured / known-good bytes. **No fuzzing.**
- **Never** write the SMP service `8d53dc1d…` / char `da2e7828…` — it can flash firmware or reset
  the device. (fs/shell mgmt groups are disabled, but writes are still brick-risk.)
- Uploads only ever corrupt the rewritable pattern store (recoverable by re-upload), never the
  firmware. There is no BLE read-back, so **keep `.bin` backups**.
