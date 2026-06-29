#!/usr/bin/env python3
"""Control the Magene L308 over raw BLE (vendor GATT). See spec/L308-ble-protocol.md.

Channels (from the GATT dump + capture):
  8ce5cc05  vendor-A : control commands + responses (notify). 94f1=query,
            94f2=set, device replies 94f5...
  8ce5cc06  vendor-B : bulk pattern/emoji upload (not used here yet)
  da2e7828  SMP/DFU  : NEVER WRITE (firmware mgmt, brick risk)

Settings command (decoded, confident):
  94 f2 23 f0 | 01 [brake] [sleep_on] [timeout_lo] [timeout_hi] 01
  query with: 94 f1 23 f0 01  -> notify 94 f5 23 f0 01 BB SS TL TH 01

Usage:
  l308_send.py read-settings [--name L308]
  l308_send.py set-settings [--brake 0|1] [--sleep 0|1] [--timeout SECONDS] [--name]
  l308_send.py list-patterns [--name]
  l308_send.py listen [--seconds 20] [--name]
  l308_send.py raw <hexbytes> [--char A|B] [--name] [--response]

By default the first L308 found is targeted. All control writes are
write-without-response (wt=1), matching the app.
"""
import argparse
import asyncio
import sys

from bleak import BleakScanner, BleakClient

CMD_CHAR = "8ce5cc05-0a4d-11e9-ab14-d663bd873d93"   # vendor-A control
DATA_CHAR = "8ce5cc06-0a4d-11e9-ab14-d663bd873d93"  # vendor-B bulk
SMP_CHAR = "da2e7828-fbce-4e01-ae9e-261174997c48"   # NEVER WRITE

# Observed opening write from the app (a handshake/hello). Harmless to replay.
HANDSHAKE = bytes.fromhex("80f10101000000000000000000")
SETTINGS_QUERY = bytes.fromhex("94f123f001")
PATTERNS_QUERY = bytes.fromhex("94f123e201")


async def pick(name, timeout=10.0):
    found = await BleakScanner.discover(timeout=timeout, return_adv=True)
    cands = []
    for d, adv in found.values():
        nm = d.name or adv.local_name or ""
        if name.lower() in nm.lower():
            cands.append((d, adv.rssi, nm))
    if not cands:
        print(f"No device matching {name!r}. Shake it to wake it and retry.")
        return None
    cands.sort(key=lambda x: x[1], reverse=True)
    d, rssi, nm = cands[0]
    print(f"Connecting to {nm} (rssi={rssi}) ...")
    return d


class Collector:
    """Collects notifications, with an event to await the next one."""

    def __init__(self):
        self.items = []
        self._ev = asyncio.Event()

    def cb(self, _sender, data):
        b = bytes(data)
        self.items.append(b)
        print(f"  <- notify {b.hex()}")
        self._ev.set()

    async def wait(self, timeout=3.0):
        try:
            await asyncio.wait_for(self._ev.wait(), timeout)
        except asyncio.TimeoutError:
            pass
        self._ev.clear()


def parse_settings(b):
    # 94 f5/f2/f1 23 f0 01 BB SS TL TH 01
    if len(b) >= 10 and b[2] == 0x23 and b[3] == 0xf0:
        return {"brake": b[5], "sleep_on": b[6],
                "sleep_timeout_s": b[7] | (b[8] << 8)}
    return None


async def with_client(name, fn):
    dev = await pick(name)
    if not dev:
        sys.exit(1)
    async with BleakClient(dev) as client:
        print("Connected.")
        await fn(client)


async def do_handshake(client, col):
    await client.write_gatt_char(CMD_CHAR, HANDSHAKE, response=False)
    await col.wait()


async def read_settings(client, col, do_hs=True):
    await client.start_notify(CMD_CHAR, col.cb)
    if do_hs:
        await do_handshake(client, col)
    await client.write_gatt_char(CMD_CHAR, SETTINGS_QUERY, response=False)
    await col.wait()
    for b in col.items:
        s = parse_settings(b)
        if s:
            return s
    return None


async def cmd_read_settings(args):
    async def fn(client):
        col = Collector()
        s = await read_settings(client, col, do_hs=not args.no_handshake)
        print("\nSETTINGS:", s if s else "(no settings response seen)")
    await with_client(args.name, fn)


async def cmd_set_settings(args):
    async def fn(client):
        col = Collector()
        cur = await read_settings(client, col, do_hs=not args.no_handshake)
        if not cur:
            print("Could not read current settings; aborting to avoid clobber.")
            return
        print("current:", cur)
        brake = args.brake if args.brake is not None else cur["brake"]
        sleep_on = args.sleep if args.sleep is not None else cur["sleep_on"]
        timeout = args.timeout if args.timeout is not None \
            else cur["sleep_timeout_s"]
        payload = bytes([0x94, 0xf2, 0x23, 0xf0, 0x01, brake & 0xff,
                         sleep_on & 0xff, timeout & 0xff, (timeout >> 8) & 0xff,
                         0x01])
        print("writing: ", payload.hex())
        await client.write_gatt_char(CMD_CHAR, payload, response=False)
        await col.wait()
        # read back
        col.items.clear()
        await client.write_gatt_char(CMD_CHAR, SETTINGS_QUERY, response=False)
        await col.wait()
        for b in col.items:
            s = parse_settings(b)
            if s:
                print("after:  ", s)
                return
    await with_client(args.name, fn)


async def cmd_list_patterns(args):
    async def fn(client):
        col = Collector()
        await client.start_notify(CMD_CHAR, col.cb)
        if not args.no_handshake:
            await do_handshake(client, col)
        await client.write_gatt_char(CMD_CHAR, PATTERNS_QUERY, response=False)
        await col.wait()
        for b in col.items:
            # 94 f5 23 e2 01 CC ?? <id*4 LE> ...
            if len(b) >= 6 and b[2] == 0x23 and b[3] == 0xe2:
                count = b[5]
                ids = []
                off = 7
                while off + 4 <= len(b) and len(ids) < count:
                    val = int.from_bytes(b[off:off + 4], "little")
                    if val:
                        ids.append(val)
                    off += 4
                print(f"\n{count} patterns, ids: {[hex(i) for i in ids]}")
    await with_client(args.name, fn)


async def cmd_pattern(args):
    idx = args.n - 1  # app uses a 0-based slot index
    payload = bytes([0x94, 0xf2, 0x23, 0xe1, 0x01, 0x01, idx & 0xff, 0, 0, 0])

    async def fn(client):
        col = Collector()
        await client.start_notify(CMD_CHAR, col.cb)
        if not args.no_handshake:
            await do_handshake(client, col)
        print(f"selecting slot {args.n} (idx {idx}): {payload.hex()}")
        await client.write_gatt_char(CMD_CHAR, payload, response=False)
        await col.wait()
    await with_client(args.name, fn)


async def cmd_listen(args):
    async def fn(client):
        col = Collector()
        for ch in (CMD_CHAR, DATA_CHAR):
            try:
                await client.start_notify(ch, col.cb)
            except Exception as e:
                print(f"notify {ch[:8]} failed: {e}")
        print(f"Listening {args.seconds}s for notifications ...")
        await asyncio.sleep(args.seconds)
    await with_client(args.name, fn)


async def cmd_raw(args):
    if args.char == "B":
        char = DATA_CHAR
    else:
        char = CMD_CHAR
    payload = bytes.fromhex(args.hexbytes)
    if char == SMP_CHAR:
        print("Refusing to write SMP characteristic.")
        return

    async def fn(client):
        col = Collector()
        await client.start_notify(CMD_CHAR, col.cb)
        print(f"writing {payload.hex()} to {char[:8]} (response={args.response})")
        await client.write_gatt_char(char, payload, response=args.response)
        await col.wait(timeout=4.0)
    await with_client(args.name, fn)


def main():
    ap = argparse.ArgumentParser(description="Magene L308 BLE control")
    ap.add_argument("--name", default="L308", help="device name substring")
    ap.add_argument("--no-handshake", action="store_true",
                    help="skip the 80f1 opening handshake")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("read-settings")

    ss = sub.add_parser("set-settings")
    ss.add_argument("--brake", type=int, choices=[0, 1])
    ss.add_argument("--sleep", type=int, choices=[0, 1])
    ss.add_argument("--timeout", type=int, help="auto-sleep seconds")

    sub.add_parser("list-patterns")

    pt = sub.add_parser("pattern")
    pt.add_argument("n", type=int, help="slot number (1-based, as shown in app)")

    ls = sub.add_parser("listen")
    ls.add_argument("--seconds", type=int, default=20)

    rw = sub.add_parser("raw")
    rw.add_argument("hexbytes")
    rw.add_argument("--char", choices=["A", "B"], default="A")
    rw.add_argument("--response", action="store_true")

    args = ap.parse_args()
    fns = {"read-settings": cmd_read_settings, "set-settings": cmd_set_settings,
           "list-patterns": cmd_list_patterns, "pattern": cmd_pattern,
           "listen": cmd_listen, "raw": cmd_raw}
    asyncio.run(fns[args.cmd](args))


if __name__ == "__main__":
    main()
