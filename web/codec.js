// L308 light_mode.bin codec — pure logic, no DOM/BLE (so it's node-testable).
// Format (decoded): file = 5-byte header + N × 186-byte records.
//   header  = 00 01 <count> 04 00
//   record  = id[4 LE] type[2] ...fields... bitmap(100 bits from byte 11, LSB-first)
// Grid: full 10×10; LED index = row*10 + col; corners 0,9,90,99 are unused (96 LEDs).
// Bitmap byte = 11 + (idx>>3), bit = idx & 7.
// checksum (upload header) = CRC16/XMODEM over the whole file.

export const REC = 186, HDR = 5, BMP_OFF = 11, COLS = 10, ROWS = 10;
export const CORNERS = new Set([0, 9, 90, 99]);

export const ledIndex = (row, col) => row * COLS + col;
export const isCorner = (row, col) => CORNERS.has(ledIndex(row, col));

export function crc16xmodem(bytes) {
  let c = 0;
  for (const x of bytes) {
    c ^= x << 8;
    for (let i = 0; i < 8; i++) c = (c & 0x8000) ? ((c << 1) ^ 0x1021) & 0xffff : (c << 1) & 0xffff;
  }
  return c;
}

const le = (n, bytes) => { const a = []; for (let i = 0; i < bytes; i++) { a.push(n & 0xff); n = Math.floor(n / 256); } return a; };

// Set of LED indices (0..99) -> 13-byte bitmap (covers 100 bits).
export function ledsToBitmap(leds) {
  const bm = new Uint8Array(13);
  for (const L of leds) if (L >= 0 && L < 100) bm[L >> 3] |= (1 << (L & 7));
  return bm;
}
export function bitmapToLeds(bytes) {           // bytes = full 186 record OR 13-byte bitmap
  const bm = bytes.length === 13 ? bytes : bytes.slice(BMP_OFF, BMP_OFF + 13);
  const leds = [];
  for (let L = 0; L < 100; L++) if (bm[L >> 3] & (1 << (L & 7)) && !CORNERS.has(L)) leds.push(L);
  return leds;
}

function blank() { return new Uint8Array(REC); }
function putHead(r, id) { r.set(le(id, 4), 0); }
function putBitmap(r, leds) { r.set(ledsToBitmap(leds), BMP_OFF); }

// --- record builders (one per type) ---
export function solidRecord(id, leds, brightnessByte = 0x12) {
  const r = blank(); putHead(r, id);
  r.set([0x01, 0x01, brightnessByte & 0xff, 0xff], 4); putBitmap(r, leds); return r;
}
export function timedRecord(id, leds, { pulsing = false, intervalSec = 2, minPct = 20, maxPct = 80 } = {}) {
  const r = blank(); putHead(r, id);
  // offset7 = bit7(mode: 1=pulsing) | interval-low-bits (flashing ≈ sec+4)
  const b7 = (pulsing ? 0x80 : 0x00) | (pulsing ? 0 : (intervalSec + 4)) & 0x7f;
  r.set([0x03, 0x01, 0x18, b7, b7, maxPct & 0xff, minPct & 0xff], 4); putBitmap(r, leds); return r;
}

// Multi-frame record — powers BOTH GIF (type 0x02, param=fps) and scrolling text
// (type 0x04, param=scroll speed). Layout per the captured records:
//   [id] [type] [count] then count × ( 18 <param> 00 00 00 + 13-byte bitmap )
// Each frame block = 18 bytes; first starts at offset 6; max 10 frames.
export function framesRecord(id, type, frames, param) {
  const r = blank(); putHead(r, id);
  r[4] = type & 0xff; r[5] = frames.length & 0xff;
  frames.forEach((leds, i) => {
    const base = 6 + i * 18;
    r[base] = 0x18; r[base + 1] = param & 0xff;            // marker + fps/speed
    r.set(ledsToBitmap(leds), base + 5);                   // 13-byte bitmap
  });
  return r;
}
export const MAX_FRAMES = 10;
// pull the per-frame LED sets back out (for editing / preview)
export function framesFromRecord(r) {
  const n = r[5], out = [];
  for (let i = 0; i < n; i++) {
    const base = 6 + i * 18;
    out.push(bitmapToLeds(r.slice(base + 5, base + 5 + 13)));
  }
  return out;
}

// --- file build / parse ---
export function buildFile(records) {
  const body = new Uint8Array(records.length * REC);
  records.forEach((r, i) => body.set(r, i * REC));
  const out = new Uint8Array(HDR + body.length);
  out.set([0x00, 0x01, records.length & 0xff, 0x04, 0x00], 0);
  out.set(body, HDR);
  return out;
}
export function parseFile(buf) {
  const count = buf[2], recs = [];
  for (let i = 0; i < (buf.length - HDR) / REC; i++) recs.push(buf.slice(HDR + i * REC, HDR + (i + 1) * REC));
  return { count, records: recs };
}
export const recordId = (r) => r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24);
export const recordType = (r) => r[4];

// next free id in the 0x8aXX family the app uses for user patterns
export function nextId(records) {
  let max = 0x8a00; for (const r of records) max = Math.max(max, recordId(r)); return max + 1;
}

// --- import helpers ---
// imageData (any size) -> set of lit LED indices, nearest-sampling to 10×10 with threshold.
export function imageToLeds(imgData, w, h, threshold = 128) {
  const leds = [];
  for (let row = 0; row < ROWS; row++) for (let col = 0; col < COLS; col++) {
    if (CORNERS.has(ledIndex(row, col))) continue;
    const sx = Math.floor((col + 0.5) / COLS * w), sy = Math.floor((row + 0.5) / ROWS * h);
    const o = (sy * w + sx) * 4, lum = 0.299 * imgData[o] + 0.587 * imgData[o + 1] + 0.114 * imgData[o + 2];
    const a = imgData[o + 3];
    if (a > 64 && lum >= threshold) leds.push(ledIndex(row, col));
  }
  return leds;
}

// build the upload frames for a file (start/header/chunks/commit)
export function uploadFrames(file, ts, chunkSize = 236) {
  const size = file.length, crc = crc16xmodem(file);
  const chunks = []; for (let i = 0; i < size; i += chunkSize) chunks.push(file.slice(i, i + chunkSize));
  const start = Uint8Array.from([0x94, 0xf2, 0x01, 0x24, 0x01, 0, 0, 0, 0, 0x01, 0x00, ...le(ts, 4), 0, 0, 0, 0, 0, 0]);
  const header = Uint8Array.from([0x94, 0xf2, 0x01, 0x25, 0x0b, 0, 0, 0, 0, 0, 0, ...le(size, 4), ...le(chunks.length, 2), ...le(crc, 2), 0, 0, 0, 0, ...[...'light_mode.bin'].map(c => c.charCodeAt(0))]);
  const commit = Uint8Array.from([0x94, 0xf2, 0x01, 0x24, 0x02, 0, 0, 0, 0, 0x01, 0x02, ...le(ts, 4), 0, 0, 0, 0, 0, 0]);
  const chunkFrames = chunks.map((c, i) => Uint8Array.from([0x94, 0xf2, 0x01, 0x26, ...le(i + 1, 2), ...le(c.length, 2), ...c]));
  return { start, header, chunkFrames, commit, size, crc, nchunks: chunks.length };
}
