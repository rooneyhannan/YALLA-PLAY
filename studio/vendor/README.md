# Vendored

- `basic-pitch.js`: [@spotify/basic-pitch](https://github.com/spotify/basic-pitch-ts)
  1.0.1 with TensorFlow.js, bundled for the browser with esbuild:
  `export { BasicPitch, outputToNotesPoly, addPitchBendsToNoteEvents, noteFramesToTime } from '@spotify/basic-pitch'`
  and `export { setBackend, getBackend } from '@tensorflow/tfjs'`,
  `export { setWasmPaths } from '@tensorflow/tfjs-backend-wasm'`.
  Also bundled: `@tensorflow/tfjs-backend-wasm` 3.21 with its `Fill` kernel
  patched to default the dtype like the CPU backend (Basic Pitch leaves it out).
  Apache License 2.0, see `LICENSE-basic-pitch.txt`.
- `wasm/`: the WebAssembly binaries of `@tensorflow/tfjs-backend-wasm` 3.21 (Apache 2.0).
- `model/`: the Basic Pitch model from the same package.

Kept in the repository so the Studio runs without any CDN.
