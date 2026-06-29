# Magene L308 — unofficial interop tools

Control a Magene **L308** smart taillight directly over Bluetooth LE — select patterns, set
brightness, toggle the brake-alert, change the auto-sleep timeout, and upload your own pattern
store — without the official app. Works on region-locked units too (the region lock is
app/cloud-side, not enforced on the device).

> **Unofficial.** Not affiliated with, endorsed by, or supported by Magene. "Magene" and
> "L308" are trademarks of their respective owner, used here nominatively to identify the
> device this project interoperates with. For interoperability/repair on hardware you own.
> No warranty — use at your own risk.

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

## License
Code: **MIT** (`LICENSE`). Protocol spec: **CC-BY-4.0** (`spec/LICENSE`).
