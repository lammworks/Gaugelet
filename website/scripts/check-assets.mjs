import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../public/images");
const expected = {
  "gaugelet-social.jpg": [1200, 630],
  "product-hunt-thumbnail.jpg": [240, 240],
  "product-hunt-gallery-1.jpg": [1270, 760],
  "product-hunt-gallery-2.jpg": [1270, 760],
  "product-hunt-gallery-3-themes.jpg": [1270, 760],
  "product-hunt-gallery-4-notification.jpg": [1270, 760],
};

const expectedPng = {
  "gaugelet-dashboard.png": [1090, 1443],
};

function pngDimensions(buffer) {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (!buffer.subarray(0, 8).equals(signature) || buffer.toString("ascii", 12, 16) !== "IHDR") {
    throw new Error("not PNG data");
  }
  return [buffer.readUInt32BE(16), buffer.readUInt32BE(20)];
}

function jpegDimensions(buffer) {
  if (buffer[0] !== 0xff || buffer[1] !== 0xd8) throw new Error("not JPEG data");
  let offset = 2;
  while (offset + 8 < buffer.length) {
    if (buffer[offset] !== 0xff) { offset += 1; continue; }
    const marker = buffer[offset + 1];
    if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
      return [buffer.readUInt16BE(offset + 7), buffer.readUInt16BE(offset + 5)];
    }
    if (marker === 0xd8 || marker === 0xd9) { offset += 2; continue; }
    const length = buffer.readUInt16BE(offset + 2);
    if (length < 2) throw new Error("invalid JPEG segment");
    offset += 2 + length;
  }
  throw new Error("JPEG dimensions not found");
}

for (const [filename, dimensions] of Object.entries(expected)) {
  const buffer = readFileSync(resolve(root, filename));
  const actual = jpegDimensions(buffer);
  if (actual[0] !== dimensions[0] || actual[1] !== dimensions[1]) {
    throw new Error(`${filename} is ${actual.join("x")}, expected ${dimensions.join("x")}`);
  }
  if (filename === "product-hunt-thumbnail.jpg" && buffer.length >= 3_000_000) {
    throw new Error(`${filename} exceeds Product Hunt's 3 MB limit`);
  }
}

for (const [filename, dimensions] of Object.entries(expectedPng)) {
  const actual = pngDimensions(readFileSync(resolve(root, filename)));
  if (actual[0] !== dimensions[0] || actual[1] !== dimensions[1]) {
    throw new Error(`${filename} is ${actual.join("x")}, expected ${dimensions.join("x")}`);
  }
}

console.log(`Verified ${Object.keys(expected).length + Object.keys(expectedPng).length} launch images.`);
