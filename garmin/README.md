# L308 Light — Garmin Connect IQ controller

Cycle the displayed pattern on a **Magene L308** taillight (prev/next) from a Garmin
Connect IQ device over BLE — the same "change pattern" action the Magene C606 head unit
does. MVP = a **device app** with button input; targets any CIQ device that supports
`Toybox.BluetoothLowEnergy` (CIQ ≥ 3.1).

Protocol is documented in `../spec/L308-ble-protocol.md`; the known-good Python reference
is `../l308_send.py`. **Only** the vendor char `8ce5cc05` is ever touched —
the SMP/firmware service is never referenced (brick risk).

## Layout
```
manifest.xml          type=watch-app, minApiLevel 3.1.0, BLE permission, BLE-capable products
monkey.jungle         build config
resources/            strings, launcher icon
source/
  Protocol.mc         UUIDs + exact command bytes + reply parsing (mirror of l308_send.py)
  L308BleManager.mc   BLE core: scan -> connect -> notify -> handshake -> list -> select
  L308App.mc          app entry; owns the BLE manager
  L308View.mc         status screen: "Pattern X / N"
  L308Delegate.mc     UP/page-prev/swipe-left = prev, DOWN/page-next/swipe-right = next
```

## One-time setup (nothing is installed yet)
1. **Connect IQ SDK** — install the SDK Manager from
   https://developer.garmin.com/connect-iq/sdk/ , then download a recent SDK and the device
   files for your targets (at least Forerunner 965).
2. **VS Code + “Monkey C” extension** (official Garmin) — gives the compiler, simulator, and
   the manifest **Edit Products / Edit Permissions** editors.
3. **Developer key** (signs every build):
   ```sh
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key -nocrypt
   ```
   Point the extension at `developer_key` (Settings → *Monkey C: Developer Key Path*). It’s
   gitignored.

## Build & run
- **CLI build (what we use):** signed `L308.prg` for the FR965 is produced with:
  ```sh
  SDKBIN="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/<sdk-version>/bin"
  "$SDKBIN/monkeyc" -d fr965 -f monkey.jungle -o L308.prg -y developer_key -w
  ```
  (Swap `-d fr965` for any other BLE-capable product to retarget.)
- **Simulator (optional):** `"$SDKBIN/monkeydo" L308.prg fr965`, or VS Code *Monkey C: Run
  App*. ⚠️ The simulator has **no real BLE** — it only validates the build and UI; scanning
  won’t find the light.
- **Sideload to the watch (the only real BLE test):** connect the FR965 by USB; on macOS it
  mounts via **MTP**, so use **OpenMTP** to copy `L308.prg` into the watch’s
  **`GARMIN/Apps/`** folder, then eject. The app then appears in the apps/activities list.

## On-device test
1. Wake the L308 (shake it) so it advertises `L308_xxxx`, and keep it close.
2. Open the app; approve the BLE prompt if shown.
3. Expect: `Scanning… → Connecting… → Ready`, then `Pattern X / N`.
4. **UP = previous, DOWN = next** (or swipe left/right on touch); the light’s pattern should
   change and wrap at the ends.

## Cross-check (independent byte oracle)
From the Mac, drive the same light with the known-good Python tool and compare:
```sh
cd .. && .venv/bin/python l308_send.py list-patterns   # confirms the count the app reads
.venv/bin/python l308_send.py pattern 3                # confirms select bytes match
```

## Notes / next steps
- All writes use `WRITE_TYPE_DEFAULT`, which in the Connect IQ API means
  **write-without-response** (`wt=1`, matching the app; the acknowledged variant is
  `WRITE_TYPE_WITH_RESPONSE`). GATT ops are chained one-at-a-time through their completion
  callbacks. *If the pattern count never loads on-device*, the likely cause is a no-response
  write not firing `onCharacteristicWrite` on your firmware — switch the **handshake + list**
  writes to `WRITE_TYPE_WITH_RESPONSE` (the char supports it) for guaranteed callbacks, and
  keep **select** as `WRITE_TYPE_DEFAULT`.
- **Widget (Phase 2):** reuse `Protocol.mc` + `L308BleManager.mc` + `L308View.mc`; add a thin
  widget shell with `type="widget"` (a `.prg` is one app type, so it’s a parallel build).
- **Di2 / bike buttons (research only):** Connect IQ can’t capture Di2 hidden-button presses
  (`AntPlus.Shifting` reports gear positions, not buttons, and excludes Shimano). The only
  sanctioned on-bar trigger is `AntPlus.Shifting` gear-change detection on **SRAM AXS** —
  experimental; default input stays device keys + touch.
