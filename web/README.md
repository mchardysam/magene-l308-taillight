# L308 Manager (Web Bluetooth)

An unofficial, install-free manager for the Magene L308 taillight, including
**region-locked units** (the region lock is app-side, not enforced on the device). Pure static page;
all BLE happens locally in the browser. Protocol reference: [`../spec/L308-ble-protocol.md`](../spec/L308-ble-protocol.md).

## Run it
Web Bluetooth needs a **secure context** (HTTPS or `localhost`) and **Chrome/Edge
on desktop or Android** (not iOS Safari — that's a later Capacitor build).

- **Local:** `python3 -m http.server 8753` in this folder, open
  `http://localhost:8753` in Chrome. (`localhost` counts as secure.)
- **Host (free):** push this folder to a GitHub repo → Settings → Pages → deploy
  from branch. The `https://…github.io/…` URL satisfies the secure-context rule.

Shake the light to wake it, click **Connect light**, pick `L308_xxxx`.

## v0 — works now (fully-decoded protocol)
- Connect + handshake
- **Settings:** read + set brake alert, auto-sleep, sleep timeout
- **Patterns:** list device slots + tap to display one
- **Push / backup:** upload a `light_mode.bin` (e.g. one exported by our Python
  tools), or save a loaded file. ⚠️ Pushing replaces the whole store; there is no
  read-back, so keep backups.

## Next
- **Pixel editor** with the real panel shape (10×10 minus 4 corners = 96 LEDs) —
  needs the full grid bit-map finished first.
- Add / delete / reorder / **edit** patterns (incl. changing a pattern's effect type)
- Brightness: solid (byte 6) + flashing/pulsing min/max range. **GIF/text have no known
  brightness field** (1-bit on/off bitmaps) — would need hardware experimentation to find one.
- Image / GIF / text import → bitmap
- Live mode (drive the panel from the browser)

## Safety
Never writes the SMP/DFU service (`8d53dc1d…`) — only the vendor command/data
chars. A bad upload can only corrupt the rewritable pattern store, not brick the light.

## Disclaimer
Unofficial — not affiliated with or endorsed by Magene. "Magene"/"L308" are trademarks of
their owner, used nominatively. For interoperability on hardware you own. No warranty.
