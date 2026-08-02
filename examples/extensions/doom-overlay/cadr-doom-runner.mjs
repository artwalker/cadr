#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}

const wasmPath = args.get("--wasm");
const wadPath = args.get("--wad");
const fps = Number(args.get("--fps") ?? "35");
if (!wasmPath || !wadPath || !Number.isFinite(fps) || fps <= 0) {
  process.stderr.write("usage: cadr-doom-runner --wasm FILE --wad FILE --fps N --format ansi-lines\n");
  process.exit(2);
}

const buildDir = path.dirname(path.resolve(wasmPath));
const doomJsPath = path.join(buildDir, "doom.js");
if (!fs.existsSync(doomJsPath)) {
  throw new Error(`DOOM JavaScript glue not found at ${doomJsPath}`);
}

const doomJs = fs.readFileSync(doomJsPath, "utf8");
const moduleExports = { exports: {} };
const nativeRequire = createRequire(doomJsPath);
new Function("module", "exports", "__dirname", "__filename", "require", doomJs)(
  moduleExports,
  moduleExports.exports,
  buildDir,
  doomJsPath,
  nativeRequire,
);

const createDoomModule = moduleExports.exports;
const wad = Array.from(fs.readFileSync(wadPath));
const module = await createDoomModule({
  locateFile: (name) => (name.endsWith(".wasm") ? path.resolve(wasmPath) : path.join(buildDir, name)),
  print: () => {},
  printErr: () => {},
  preRun: [
    (runtime) => {
      runtime.FS_createPath("/", "doom", true, true);
      runtime.FS_createDataFile("/doom", "doom1.wad", wad, true, false);
    },
  ],
});

const strings = ["doom", "-iwad", "/doom/doom1.wad"];
const pointers = strings.map((value) => {
  const pointer = module._malloc(value.length + 1);
  for (let index = 0; index < value.length; index += 1) module.setValue(pointer + index, value.charCodeAt(index), "i8");
  module.setValue(pointer + value.length, 0, "i8");
  return pointer;
});
const argv = module._malloc(pointers.length * 4);
pointers.forEach((pointer, index) => module.setValue(argv + index * 4, pointer, "i32"));
module._doomgeneric_Create(pointers.length, argv);
pointers.forEach((pointer) => module._free(pointer));
module._free(argv);

const sourceWidth = module._DG_GetScreenWidth();
const sourceHeight = module._DG_GetScreenHeight();
const framePointer = module._DG_GetFrameBuffer();
const columns = Math.max(20, Number(process.env.CADR_DOOM_COLUMNS ?? 80));
const rows = Math.max(8, Number(process.env.CADR_DOOM_ROWS ?? 25));

function pixel(x, y) {
  const sourceX = Math.min(sourceWidth - 1, Math.floor((x * sourceWidth) / columns));
  const sourceY = Math.min(sourceHeight - 1, Math.floor((y * sourceHeight) / (rows * 2)));
  const argb = module.getValue(framePointer + (sourceY * sourceWidth + sourceX) * 4, "i32");
  return [(argb >>> 16) & 255, (argb >>> 8) & 255, argb & 255];
}

function renderFrame() {
  const lines = [];
  for (let row = 0; row < rows; row += 1) {
    let line = "";
    let previous = "";
    for (let column = 0; column < columns; column += 1) {
      const upper = pixel(column, row * 2);
      const lower = pixel(column, row * 2 + 1);
      const color = `\u001b[38;2;${upper.join(";")}m\u001b[48;2;${lower.join(";")}m`;
      if (color !== previous) {
        line += color;
        previous = color;
      }
      line += "▀";
    }
    lines.push(`${line}\u001b[0m`);
  }
  process.stdout.write(`${lines.join("\f")}\n`);
}

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  input += chunk;
  for (;;) {
    const newline = input.indexOf("\n");
    if (newline < 0) break;
    const line = input.slice(0, newline);
    input = input.slice(newline + 1);
    const match = /^KEY (\d+) ([01])$/.exec(line);
    if (match) module._DG_PushKeyEvent(Number(match[2]), Number(match[1]));
  }
});

const timer = setInterval(() => {
  module._doomgeneric_Tick();
  renderFrame();
}, Math.max(1, Math.floor(1000 / fps)));

function stop() {
  clearInterval(timer);
  process.exit(0);
}
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
