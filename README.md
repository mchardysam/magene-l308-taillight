# Magene L308 — unofficial interop tools

<p align="center">
  <img src="docs/hero.svg" width="660"
       alt="The L308's 10×10 LED panel rendering a heart, an alert arrow, and a scrolling-text glyph">
</p>

Control a Magene **L308** smart taillight directly over Bluetooth LE — select patterns, set
brightness, toggle the brake-alert, change the auto-sleep timeout, and upload your own pattern
store — without the official app. Works on region-locked units too (the region lock is
app/cloud-side, not enforced on the device).

> **Unofficial.** Not affiliated with, endorsed by, or supported by Magene. "Magene" and
> "L308" are trademarks of their respective owner, used here nominatively to identify the
> device this project interoperates with. For interoperability/repair on hardware you own.
> No warranty — use at your own risk.

## What the L308 is
The L308 isn't a normal blinky. Its rear face is a **10×10 grid of 96 red LEDs** — a little
programmable dot-matrix display. Beyond the usual solid / flash / pulse, you can show **custom
pixel art, multi-frame animations, and scrolling text**, and it has an accelerometer
**brake-alert** (flares when you slow) plus an **auto-sleep** timeout. That programmability is
what sets it apart from just about every other taillight — and it's exactly what makes a proper
control tool worthwhile.

**Specs at a glance** *(per Magene's published figures — verify current details before buying):*

| Spec | Detail |
|---|---|
| **Display** | 96 COB LEDs in a 10×10 matrix — fully drawable (pixel art, animations, scrolling text) |
| **Brightness** | up to ~30 lumens, claimed visible to ~800 m |
| **Brake alert** | accelerometer detects braking → ~3 s high-intensity flash |
| **Auto sleep/wake** | motion-sensing; sleeps after 1–10 min idle (configurable), wakes on movement |
| **Battery** | USB rechargeable; up to ~50 h (≈10 h with rich animations), ~80% in ~1.5 h |
| **Build** | 23 g, IPX6 water-resistant |
| **Mounts** | seatpost and saddle-rail versions |

## Why this exists
1. **Better, simpler control.** All that programmability is buried deep in the OnelapFit app.
   I wanted to draw a pattern, set the brightness, and push it to the light in a few seconds
   from a browser — no account, no app-store install, no menu-diving. So I decoded the BLE
   protocol and built a focused tool around it.
2. **Region-locked units.** Some L308s are region-locked *in the app*, even though the lock
   isn't enforced on the device. These tools talk to the light directly, so if you own the
   hardware you can use it regardless.

It's interoperability for hardware you own — nothing more. Not affiliated with Magene; if
they'd like something changed, I'm happy to hear from them.

## What's here
- **[`spec/`](spec/L308-ble-protocol.md)** — the BLE + `light_mode.bin` protocol reference (source of truth).
- **[`web/`](web/)** — an install-free **Web Bluetooth** manager: connect, draw/edit patterns
  (solid · flashing · pulsing · GIF · scrolling text), manage settings, and push to the light.
  Runs in Chrome/Edge (desktop or Android); deploy it to GitHub Pages.
- **Python CLI** (`l308_send.py`, `l308_upload.py`, `l308_explore.py`) — needs `bleak`.

A **Garmin Connect IQ** app (cycle patterns from a watch/Edge) is in the works.

## Quick start — Python
```sh
python3 -m venv .venv && .venv/bin/pip install bleak
.venv/bin/python l308_send.py --name <NAME> read-settings    # brake / sleep / timeout
.venv/bin/python l308_send.py --name <NAME> list-patterns    # stored ids + current slot
.venv/bin/python l308_send.py --name <NAME> pattern 3        # show slot 3 (1-based)
.venv/bin/python l308_upload.py store.bin --name <NAME>      # replace the on-device store
```
`<NAME>` is any substring of the light's advertised name (e.g. `L308_4B91`). `l308_explore.py`
scans and dumps a device's GATT.

## Quick start — web app
```sh
cd web && python3 -m http.server 8753
```
Open `http://localhost:8753` in Chrome/Edge and click **Connect light**. Or push `web/` to a
GitHub Pages site — the `https://` URL satisfies Web Bluetooth's secure-context requirement.
(Web Bluetooth works on Chrome/Edge desktop + Android; **not** iOS Safari.)

## Protocol
Fully documented in **[`spec/L308-ble-protocol.md`](spec/L308-ble-protocol.md)**: GATT map,
command framing, settings, pattern list/select, the chunked file-upload sequence, and the
`light_mode.bin` record format (solid/flashing/pulsing/gif/text, brightness + timing fields).
Derived by observing our own hardware; the `web/` and `garmin/` clients both implement it.

## Safety
- Replay only known-good bytes — no fuzzing.
- **Never** write the SMP/DFU service (`8d53dc1d…`) — it can flash or reset firmware (**brick risk**).
  These tools only touch the vendor command/data characteristics.
- The light has **no pattern read-back**: an upload replaces the whole store with no undo, so
  keep `.bin` backups (the web app's library is your source of truth).

## Support
This is a free, unofficial side project. If it saved you some time, you can
[sponsor development](https://github.com/sponsors/mchardysam) — entirely optional, and
the tools stay free either way.

## License
Code: **MIT** (`LICENSE`). Protocol spec: **CC-BY-4.0** (`spec/LICENSE`).
