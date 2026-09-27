// Runs Basic Pitch off the page's thread, on WebAssembly: fast on every
// device and independent of the graphics card, which some browsers offer
// but cannot run TensorFlow on. Receives mono samples at 22 050 Hz,
// answers with the engine, progress messages and finally the notes.
self.onmessage = async ({ data: { samples } }) => {
  try {
    // The same version as this worker, so no cached older copy mixes in.
    const version = new URL(import.meta.url).search;
    const {
      BasicPitch, addPitchBendsToNoteEvents, noteFramesToTime, outputToNotesPoly,
      setBackend, getBackend, setWasmPaths,
    } = await import(`./vendor/basic-pitch.js${version}`);
    setWasmPaths(new URL('./vendor/wasm/', import.meta.url).href);
    let engine = 'WebAssembly';
    if (!(await setBackend('wasm').catch(() => false)) || getBackend() !== 'wasm') {
      await setBackend('cpu');
      engine = 'Prozessor (langsamer)';
    }
    self.postMessage({ engine });
    const model = new BasicPitch(new URL('./vendor/model/model.json', import.meta.url).href);
    const frames = [], onsets = [], contours = [];
    await model.evaluateModel(samples, (f, o, c) => {
      frames.push(...f);
      onsets.push(...o);
      contours.push(...c);
    }, (progress) => self.postMessage({ progress }));
    const notes = noteFramesToTime(addPitchBendsToNoteEvents(contours, outputToNotesPoly(frames, onsets, 0.5, 0.3, 11)))
      .map((n) => ({ start: n.startTimeSeconds, duration: n.durationSeconds, midi: n.pitchMidi, amplitude: n.amplitude }));
    self.postMessage({ notes });
  } catch (error) {
    self.postMessage({ error: String(error?.message ?? error) });
  }
};
