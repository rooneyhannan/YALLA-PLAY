# Vendored

- `basic-pitch.js`: [@spotify/basic-pitch](https://github.com/spotify/basic-pitch-ts)
  1.0.1 with TensorFlow.js, bundled for the browser with esbuild:
  `export { BasicPitch, outputToNotesPoly, addPitchBendsToNoteEvents, noteFramesToTime } from '@spotify/basic-pitch'`.
  Apache License 2.0, see `LICENSE-basic-pitch.txt`.
- `model/`: the Basic Pitch model from the same package.

Kept in the repository so the Studio runs without any CDN.
