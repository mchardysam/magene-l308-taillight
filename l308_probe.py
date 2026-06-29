#!/usr/bin/env python3
"""Probe the L308 for a DOWNLOAD command (read-only, educated guesses).

Upload uses 94 f2 01 24/25/26 (start/header/chunks). Since 94 f1 = query and
94 f2 = set in this protocol, a download likely mirrors it as 94 f1 01 24/25/26.
We subscribe to BOTH notify channels (cc05 control, cc06 bulk) and try the
candidates, logging every byte the device sends back. Reading only — no writes
to settings/patterns, never the SMP service.
"""
import asyncio
import sys
from bleak import BleakScanner, BleakClient

CMD = "8ce5cc05-0a4d-11e9-ab14-d663bd873d93"
DATA = "8ce5cc06-0a4d-11e9-ab14-d663bd873d93"
READ = "8ce5cc04-0a4d-11e9-ab14-d663bd873d93"
HANDSHAKE = bytes.fromhex("80f10101000000000000000000")

CANDIDATES = [
    "94f10124", "94f1012401", "94f10125", "94f1012501",
    "94f101250b", "94f101250b00", "94f10126", "94f1012601",
    "94f1012600", "94f10120", "94f1012301",
]


async def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "L308"
    found = await BleakScanner.discover(timeout=10.0, return_adv=True)
    c = [(d, adv.rssi) for d, adv in found.values()
         if name.lower() in (d.name or adv.local_name or "").lower()]
    if not c:
        print(f"no device matching {name!r}")
        return
    c.sort(key=lambda x: x[1], reverse=True)
    dev = c[0][0]
    print(f"Connecting to {dev.name} ...")
    got = []

    async with BleakClient(dev) as cl:
        print("connected. subscribing notify on cc05 + cc06")
        cl_evt = asyncio.Event()

        def mk(tag):
            def cb(_s, d):
                h = bytes(d).hex()
                print(f"  [{tag}] <- {h}")
                got.append((tag, h))
                cl_evt.set()
            return cb
        await cl.start_notify(CMD, mk("cc05"))
        await cl.start_notify(DATA, mk("cc06"))

        await cl.write_gatt_char(CMD, HANDSHAKE, response=False)
        await asyncio.sleep(0.5)

        try:
            v = await cl.read_gatt_char(READ)
            print(f"read cc04 = {v.hex()}")
        except Exception as e:
            print("read cc04 failed:", e)

        for cmd in CANDIDATES:
            print(f"\n>> trying {cmd}")
            n0 = len(got)
            await cl.write_gatt_char(CMD, bytes.fromhex(cmd), response=False)
            await asyncio.sleep(1.2)
            new = got[n0:]
            if not new:
                print("   (no response)")
            elif any(len(h) > 24 for _, h in new):
                print("   *** BULK-LOOKING RESPONSE — possible download! ***")

        print(f"\nTotal notifications: {len(got)}")


if __name__ == "__main__":
    asyncio.run(main())
