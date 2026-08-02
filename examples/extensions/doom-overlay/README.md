# DOOM Overlay Demo

This opt-in extension runs DoomGeneric as WebAssembly in a 35 FPS Cadr overlay.
It does not add a WASM runtime to the Cadr image: the adapter launches the host
`node` executable and loads locally built Emscripten `doom.js`/`doom.wasm` files.

Build the artifacts first:

```sh
./doom/build.sh
./cadr --extension ./examples/extensions/doom-overlay/index.lisp
```

Then run `/doom-overlay`. The shareware WAD is downloaded on first use. Controls
are WASD/arrows, Shift to run, F/Ctrl to fire, Space to use, 1-7 for weapons,
Tab for the map, Escape for the menu, and Q to close the overlay.

The source is pinned to DoomGeneric commit
`dcb7a8dbc7a16ce3dda29382ac9aae9d77d21284`; its GitHub archive SHA-256 is
`1bd3f7f26220494159a38d71f2847ec81b58d6bbd7c7c8d81b08993018001148`.
The host must provide `git`, `emcc`, and `node`. Missing programs are reported
explicitly and never affect the default Cadr tool set or release binary.
