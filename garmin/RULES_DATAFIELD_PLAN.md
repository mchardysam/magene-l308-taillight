# L308 Rules Data Field — design & build plan

## Context
The manual controller (device app + glance, in `source/`) works on the FR965 but **can't
run during a recorded ride** — and Connect IQ **data fields take no button/touch input**
(they're `compute()` + `onUpdate()` only). So in-ride control has to be *automatic*. This
plan covers a second, self-contained product — a **data field** — that switches the L308's
pattern by **rules over live ride data** (speed, power, radar, light/dark, etc.), with the
rider's manual pick as the base of the hierarchy.

Decided in design:
- **No polling.** Connect once at ride start, hold the connection, **write only when the
  target pattern changes**. Never read the light back.
- **Auto on/off**, configured ahead of time. Off → the field does nothing (manual rules).
- **Rules in a priority hierarchy**; first match wins, falling through to a default pattern.
- The light's **native brake mode** stays on the light — we don't replicate it.

## Why a separate product (important constraint)
Connect IQ `Storage`/`Properties` are **per app-id**. The manual app and this data field are
two different products and **cannot share settings or storage** (no IPC). That's fine — they
own different moments (off-bike vs. recorded ride). The data field is **fully self-contained**:
its own settings, its own BLE link, its own default pattern. It shares only *source* with the
app (`Protocol.mc` and a trimmed BLE link), copied or via a barrel/library.

## Verified platform facts (checked against SDK 9.2.0 this project)
- **BLE is a supported data-field runtime context** (BluetoothLowEnergy doc → App Types).
- `Activity.Info` (passed to `compute()`): `currentSpeed` (Float, m/s), `currentPower`
  (Number, W), `currentHeartRate`, `currentCadence`, `altitude`, `totalAscent`,
  `currentLocation`. **Grade is not a field** — derive from altitude/distance.
- `Toybox.AntPlus.BikeRadar` → `BikeRadarListener.onBikeRadarUpdate(targets)`, each
  `RadarTarget` has a threat level (`THREAT_LEVEL_VEHICLE_APPROACHING` /
  `_VEHICLE_FAST_APPROACHING`) and side. Needs a paired Varia.
- `Toybox.Weather.getSunset(location, moment)` / `getSunrise(...)` and
  `getCurrentConditions()` (`CONDITION_RAIN`, …) for night/weather rules.
- Reuse `Protocol.selectCmd()` / `listCmd()` / `parseListCount()` / `parseCurrentIndex()`
  already written in `source/Protocol.mc`.

## Rule hierarchy (priority stack)
Evaluate top-down each update; first satisfied rule sets the target; otherwise the default:
1. **Battery saver** (cap): light battery < X% → forced steady low-power pattern (top, so it
   can't be overridden into a power-hungry mode). *(needs reading the light's `2a19` — v3.)*
2. **Radar threat**: vehicle approaching / fast-approaching → high-visibility alert pattern.
3. **Group / courtesy**: if enabled → steady (non-flashing) pattern, so you don't strobe the
   wheel behind you. *(Optionally radar-aware: steady when only close/slow targets (riders),
   flash when a fast target (car) appears.)*
4. **Night / weather**: after `getSunset()` (or rain/fog) → brighter/flashing pattern.
5. **Speed band(s)**: e.g. > 40 km/h → P2 (configurable; optional second band).
6. **Power band** (optional): > N W → Pn.
7. **Default / base**: the rider's configured base pattern (lowest priority).

Each rule maps to a **pattern slot** the rider configures.

## No-poll engine (per `compute(info)`)
```
if (!autoEnabled) { draw(); return; }
ensureConnected();                         // connect on first compute; reconnect if dropped
if (!ready) { draw("connecting"); return; }
var target = evaluateHierarchy(info, radar, weather, battery);
target = applyHysteresis(target);          // deadband + min-dwell (below)
if (target != lastCommanded && !writePending) {
    writeSelect(target);                   // the ONLY BLE write
    lastCommanded = target;
}
draw(currentPattern, activeRuleLabel, connDot);
```
- One **list read at connect** to learn the pattern count (validate configured slots); after
  that, no reads.

## Anti-flap (so it doesn't thrash at thresholds)
- **Hysteresis / deadband** on numeric thresholds (e.g. switch up at 40, back down at 37 km/h).
- **Minimum dwell** per pattern (e.g. ≥ 10 s) before another switch.
- **Radar debounce**: require N consecutive threat frames to engage, M clear frames to release.

## Settings schema (Garmin Connect Mobile via `settings.xml` + `properties.xml`)
Patterns shown 1-based to the user, stored/sent 0-based (select uses 0-based slot).
- `autoEnabled` (bool)
- `defaultPattern` (number)
- `speedThresholdKmh1`, `speedPattern1` (+ optional band 2)
- `powerThresholdW`, `powerPattern` *(optional)*
- `radarEnabled`, `radarPattern`
- `nightEnabled`, `nightPattern`; `rainEnabled`, `rainPattern`
- `batterySaverEnabled`, `batteryPct`, `batteryPattern` *(v3)*
- `groupMode`, `groupPattern`
- Tunables (sane defaults, advanced): `hysteresisKmh`, `minDwellSec`, radar debounce counts

## Display (`onUpdate`) 
Compact, sized to the data-field cell (varies by device/layout): current pattern number +
active-rule label (e.g. `P3 · RADAR`) + a small connection dot. Keep drawing cheap.

## New files (separate project: `garmin-datafield/`)
```
manifest.xml            type="datafield", BluetoothLowEnergy permission, BLE-capable products
monkey.jungle
resources/
  settings/settings.xml + properties.xml   (the config UI + storage)
  strings/strings.xml
source/
  L308DataField.mc      WatchUi.DataField — compute()/onUpdate(); owns the engine + BLE link
  RulesEngine.mc        evaluateHierarchy() + hysteresis/dwell state
  BleLink.mc            trimmed BleDelegate: connect, list-once, writeSelect, reconnect
  Protocol.mc           shared copy of source/Protocol.mc (UUIDs + bytes)
```
Keep it a **separate project dir** (distinct app-id + `type="datafield"`); share `Protocol.mc`
by copy (or factor a small library/barrel both projects include).

## Risks / things to test early
- **Data-field memory budget** with BLE + radar + weather — data fields are tight; keep code
  lean (consider `(:typecheck)` discipline, avoid pulling the heavy interactive BLE class).
  Test a minimal connect+write field on-device first.
- **BLE + ANT radar together** in one field (two radios) — verify both run concurrently.
- **Connection lifecycle** inside a data field (connect at ride start, reconnect mid-ride).
- **Pattern count / slot validity** — read the list once; clamp/ignore out-of-range slots.

## Phasing
- **v1 (prove the loop):** auto on/off + default + one speed band, hysteresis + min-dwell,
  connect + write-on-change, minimal display. ← smallest thing that switches the light in-ride.
- **v2:** radar → alert; night/weather.
- **v3:** battery saver, group/courtesy mode, power band.

## Verification
- **Simulator:** the CIQ sim's **Data Field simulation** can play a FIT file / inject
  `Activity.Info` values, so the rule logic (thresholds, hysteresis, hierarchy) is fully
  testable in-sim. BLE is still not real in the sim → exercise the write path with seeded
  data (same preview trick as the app), final BLE on-device.
- **On-device (the real test):** add the field to a ride profile data screen, start an
  activity near the powered light, coast/sprint to cross thresholds and watch it switch;
  cross-check bytes with `../l308_send.py`.
- **Safety:** same rule as the app — only `8ce5cc05` is ever written; SMP UUIDs never appear.
