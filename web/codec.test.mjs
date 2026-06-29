// Self-contained codec tests (no captured data). Run: node codec.test.mjs
import * as c from './codec.js';

let pass = 0, fail = 0;
const eq = (a, b, msg) => { const ok = JSON.stringify(a) === JSON.stringify(b);
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${msg}${ok ? '' : `  got=${JSON.stringify(a)} want=${JSON.stringify(b)}`}`);
  ok ? pass++ : fail++; };

// 1. grid mapping: LED index = row*10+col, bitmap from byte 11, corners unused.
const sr = c.solidRecord(0x8a01, [1], 0x12);
eq([...sr.slice(4, 8)], [0x01, 0x01, 0x12, 0xff], 'solid header = 01 01 12 ff');
eq(sr[11], 0x02, 'LED 1 (row0,col1) -> byte 11 bit 1');
eq(c.solidRecord(0, [8])[12], 0x01, 'LED 8 (row0,col8) -> byte 12 bit 0');
eq(c.solidRecord(0, [91])[22], 0x08, 'LED 91 (row9,col1) -> byte 22 bit 3');
eq(c.bitmapToLeds(sr), [1], 'solidRecord bitmap round-trips');

// 2. timed records reproduce the documented flashing/pulsing byte sequences.
eq([...c.timedRecord(0, [1], { pulsing: false, intervalSec: 2, minPct: 20, maxPct: 80 }).slice(4, 11)],
   [0x03, 0x01, 0x18, 0x06, 0x06, 0x50, 0x14], 'flashing 2s 20-80 = 03 01 18 06 06 50 14');
eq([...c.timedRecord(0, [1], { pulsing: true, intervalSec: 4, minPct: 20, maxPct: 80 }).slice(4, 11)],
   [0x03, 0x01, 0x18, 0x80, 0x80, 0x50, 0x14], 'pulsing 20-80 = 03 01 18 80 80 50 14');

// 3. multi-frame GIF: two frames (TL, TR) at 10 fps.
const gif = c.framesRecord(0x8a02, 0x02, [[1], [8]], 0x0a);
eq([...gif.slice(4, 8)], [0x02, 0x02, 0x18, 0x0a], 'gif header = 02 02 18 0a');
eq([...gif.slice(24, 26)], [0x18, 0x0a], 'gif frame1 marker 18 0a at byte 24');
eq(c.framesFromRecord(gif), [[1], [8]], 'framesFromRecord round-trips');

// 4. file build/parse round-trip + upload framing consistency.
const file = c.buildFile([sr, gif]);
eq([...c.buildFile(c.parseFile(file).records)], [...file], 'buildFile(parseFile()) round-trips');
const fr = c.uploadFrames(file, 1782000000);
eq(fr.crc, c.crc16xmodem(file), 'uploadFrames crc == crc16xmodem(file)');
eq(fr.nchunks, Math.ceil(file.length / 236), 'uploadFrames chunk count');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
