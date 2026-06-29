#!/usr/bin/env python3
"""L308 BLE explorer -- scan, connect, dump GATT services/characteristics.

Scans for L308 units and dumps their GATT services/characteristics (handy for
confirming a unit exposes the writable vendor characteristic). See spec/.

Usage:
    python3 l308_explore.py                       # interactive pick
    python3 l308_explore.py --name L308           # auto-pick first name match
    python3 l308_explore.py --name L308 --out gatt.txt
    python3 l308_explore.py --out gatt.txt --timeout 8

macOS notes:
  * BLE MACs are hidden; identify the light by ADVERTISED NAME, not address.
  * Shake the light to wake it -- it stops advertising when stationary.
  * Make sure the phone app is NOT connected to the unit you're scanning.
  * First scan triggers a Bluetooth permission prompt; if a scan silently
    returns nothing, enable Terminal/iTerm under System Settings >
    Privacy & Security > Bluetooth, then re-run.
"""
import argparse
import asyncio
import sys

from bleak import BleakScanner, BleakClient

# Characteristics/services we must NEVER write to (firmware update -> brick
# risk). Includes the mcumgr/MCUboot "SMP" management service that the L308
# exposes (8d53dc1d... service / da2e7828... characteristic) -- writing there
# can flash firmware or reset the device.
DFU_OTA_HINTS = (
    "fe59", "ota", "dfu", "8ec90003",       # Nordic DFU / generic OTA
    "smp", "mcumgr",                          # SMP service by name
    "8d53dc1d", "da2e7828",                   # L308's SMP service + char
)


class Tee:
    """Write to stdout and optionally mirror everything to a file."""

    def __init__(self, path=None):
        self.fh = open(path, "w") if path else None

    def __call__(self, line=""):
        print(line)
        if self.fh:
            self.fh.write(line + "\n")

    def close(self):
        if self.fh:
            self.fh.close()


def looks_like_dfu(uuid: str, description: str) -> bool:
    blob = f"{uuid} {description}".lower()
    return any(h in blob for h in DFU_OTA_HINTS)


async def pick_device(name_filter, timeout):
    print(f"Scanning {timeout:.0f}s -- shake the light to wake it; ensure the")
    print("phone app is NOT connected to it right now.\n")
    found = await BleakScanner.discover(timeout=timeout, return_adv=True)
    items = list(found.values())  # [(device, advertisement_data), ...]
    if not items:
        print("No devices found. If this keeps happening, grant terminal")
        print("Bluetooth access in System Settings > Privacy & Security >")
        print("Bluetooth, then re-run. Also shake the light to wake it.")
        return None

    items.sort(key=lambda x: x[1].rssi, reverse=True)

    def disp_name(d, adv):
        return d.name or adv.local_name or "(no name)"

    if name_filter:
        matches = [
            (d, adv) for d, adv in items
            if name_filter.lower() in disp_name(d, adv).lower()
        ]
        if not matches:
            print(f"No advertised name contains {name_filter!r}. Seen:")
            for d, adv in items:
                print(f"    {disp_name(d, adv):<24} rssi={adv.rssi}")
            return None
        d, adv = matches[0]
        print(f"Auto-selected {disp_name(d, adv)!r} (rssi={adv.rssi}).\n")
        return d

    for i, (d, adv) in enumerate(items):
        print(f"[{i:2}] {disp_name(d, adv):<24} {d.address}  rssi={adv.rssi}")
    raw = input("\nPick the light's index: ").strip()
    try:
        return items[int(raw)][0]
    except (ValueError, IndexError):
        print("Invalid selection.")
        return None


async def dump(device, out: Tee):
    out(f"Connecting to {device.name or device.address} ...")
    async with BleakClient(device) as client:
        out(f"Connected to {device.name or device.address}\n")
        out("=" * 68)
        writable = []
        for service in client.services:
            out(f"[service] {service.uuid}  ({service.description})")
            for c in service.characteristics:
                props = ",".join(c.properties)
                line = f"    handle={c.handle:>3}  {c.uuid}  [{props}]"
                is_write = "write" in c.properties or \
                    "write-without-response" in c.properties
                if is_write:
                    writable.append((service.uuid, c.uuid, c.handle, props))
                if "read" in c.properties:
                    try:
                        val = await client.read_gatt_char(c.uuid)
                        line += f"  = {val.hex()}"
                    except Exception:
                        line += "  = (read failed)"
                if looks_like_dfu(c.uuid, c.description):
                    line += "   <-- DFU/OTA: DO NOT WRITE"
                out(line)
            out("")
        out("=" * 68)
        out("\nWRITABLE characteristics (candidate command channels):")
        if not writable:
            out("  (NONE FOUND -- if this is the China unit, the direct-BLE")
            out("   approach is likely dead. Report this.)")
        for svc, cu, h, props in writable:
            flag = "  <-- DFU/OTA, IGNORE" if looks_like_dfu(cu, "") else ""
            out(f"  service {svc}")
            out(f"    char {cu}  handle={h}  [{props}]{flag}")


async def main():
    ap = argparse.ArgumentParser(description="L308 GATT explorer")
    ap.add_argument("--name", help="advertised-name substring to auto-select")
    ap.add_argument("--out", help="also write the dump to this file")
    ap.add_argument("--timeout", type=float, default=6.0, help="scan seconds")
    args = ap.parse_args()

    device = await pick_device(args.name, args.timeout)
    if not device:
        sys.exit(1)

    out = Tee(args.out)
    try:
        await dump(device, out)
        if args.out:
            print(f"\nSaved dump to {args.out}")
    finally:
        out.close()


if __name__ == "__main__":
    asyncio.run(main())
