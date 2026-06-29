#!/usr/bin/env python3
"""Upload a light_mode.bin (pattern store) to an L308 over raw BLE.

Replicates the app's upload sequence (see spec/L308-ble-protocol.md):
  94 f2 01 24 01 …<ts>   start            -> 8ce5cc05
  94 f2 01 25 0b …<size><nchunks><crc>light_mode.bin   header  -> 8ce5cc05
  94 f2 01 26 <idx LE16><len LE16><data>  chunks (file)  -> 8ce5cc06
  94 f2 01 24 02 …<ts>   commit           -> 8ce5cc05
checksum = CRC16/XMODEM (poly 0x1021, init 0x0000) over the file.

SAFETY: only writes the vendor chars; never the SMP/DFU char. A bad file can
only corrupt the (rewritable) pattern store — it cannot brick the light.

Usage:
  l308_upload.py <file.bin> [--name L308] [--ts 1782000000] [--dry-run]
"""
import argparse
import asyncio
import sys
import time

from bleak import BleakScanner, BleakClient

CMD = "8ce5cc05-0a4d-11e9-ab14-d663bd873d93"   # control + acks (notify)
DATA = "8ce5cc06-0a4d-11e9-ab14-d663bd873d93"  # bulk chunks
HANDSHAKE = bytes.fromhex("80f10101000000000000000000")


def crc16_xmodem(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xffff if crc & 0x8000 else (crc << 1) & 0xffff
    return crc


def build_frames(f: bytes, ts: int, chunk=236):
    size = len(f)
    crc = crc16_xmodem(f)
    chunks = [f[i:i + chunk] for i in range(0, size, chunk)]
    tsb = ts.to_bytes(4, "little")
    start = bytes.fromhex("94f201240100000000") + b"\x01\x00" + tsb + b"\x00" * 6
    header = (bytes.fromhex("94f201250b000000000000")
              + size.to_bytes(4, "little")
              + len(chunks).to_bytes(2, "little")
              + crc.to_bytes(2, "little")
              + b"\x00" * 4 + b"light_mode.bin")
    chunk_frames = []
    for i, c in enumerate(chunks, start=1):   # 1-based index, as captured
        chunk_frames.append(bytes.fromhex("94f20126") + i.to_bytes(2, "little")
                            + len(c).to_bytes(2, "little") + c)
    commit = bytes.fromhex("94f201240200000000") + b"\x01\x02" + tsb + b"\x00" * 6
    return start, header, chunk_frames, commit, size, crc


async def pick(name):
    found = await BleakScanner.discover(timeout=10.0, return_adv=True)
    c = [(d, adv.rssi) for d, adv in found.values()
         if name.lower() in (d.name or adv.local_name or "").lower()]
    if not c:
        print(f"No device matching {name!r}.")
        return None
    c.sort(key=lambda x: x[1], reverse=True)
    print(f"Connecting to {c[0][0].name} (rssi={c[0][1]}) ...")
    return c[0][0]


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--name", default="L308")
    ap.add_argument("--ts", type=int, default=int(time.time()))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--chunk", type=int, default=236)
    args = ap.parse_args()

    data = open(args.file, "rb").read()
    start, header, chunks, commit, size, crc = build_frames(data, args.ts, args.chunk)
    print(f"file={args.file} size={size} crc16xmodem={crc:#06x} chunks={len(chunks)}")
    print(f"  start : {start.hex()}")
    print(f"  header: {header.hex()}")
    print(f"  commit: {commit.hex()}")
    if args.dry_run:
        print("(dry-run: not sending)")
        return

    dev = await pick(args.name)
    if not dev:
        sys.exit(1)
    async with BleakClient(dev) as cl:
        mtu = getattr(cl, "mtu_size", "?")
        print(f"Connected. MTU={mtu}")
        acks = []
        await cl.start_notify(CMD, lambda _s, d: acks.append(bytes(d)))

        async def w(char, payload, label):
            await cl.write_gatt_char(char, payload, response=False)
            await asyncio.sleep(0.05)

        await w(CMD, HANDSHAKE, "handshake"); await asyncio.sleep(0.1)
        await w(CMD, start, "start"); await asyncio.sleep(0.1)
        await w(CMD, header, "header"); await asyncio.sleep(0.1)
        for i, c in enumerate(chunks, 1):
            await w(DATA, c, f"chunk {i}")
        await asyncio.sleep(0.2)
        await w(CMD, commit, "commit"); await asyncio.sleep(0.3)
        print(f"Sent. Device notifications received: {len(acks)}")
        for a in acks[-3:]:
            print("  <-", a.hex())


if __name__ == "__main__":
    asyncio.run(main())
