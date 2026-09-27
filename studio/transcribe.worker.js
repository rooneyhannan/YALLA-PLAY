// Runs Basic Pitch off the page's thread, so the Studio stays responsive
// while it listens: receives mono samples at 22 050 Hz, answers with
// progress messages and finally the notes it heard.
import {
  BasicPitch, addPitchBendsToNoteEvents, noteFramesToTime, outputToNotesPoly,
} from './vendor/basic-pitch.js';

self.onmessage = async ({ data: { samples } }) => {
  try {
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
