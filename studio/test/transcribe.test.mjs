import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  assignFingers, assignTab, chartNotes, detectTempo, fromJson, melodyOf, midiOf, positions, quantize, slug, toJson,
} from '../transcribe.js';

const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url)));
const detected = read('./basic_pitch_badak.json').notes
  .map(([start, duration, midi, amplitude]) => ({ start, duration, midi, amplitude }));
const truth = read('../../assets/songs/badak.json').notes;

test('the melody is found among overtones and ringing strings', () => {
  const melody = melodyOf(detected);
  assert.equal(melody.length, truth.length);
  assert.deepEqual(melody.map((n) => n.midi), truth.map((n) => midiOf(n.s, n.f)));
});

test('the tempo and the start of the song are found', () => {
  const tempo = detectTempo(melodyOf(detected));
  assert.equal(tempo.bpm, 90);
  assert.ok(Math.abs(tempo.offset - 4) < 0.02, `offset ${tempo.offset}`);
});

test('the recording becomes the song: every note at its step and pitch', () => {
  const notes = chartNotes(detected, detectTempo(melodyOf(detected)));
  assert.equal(notes.length, truth.length);
  notes.forEach((n, i) => {
    assert.equal(n.t, truth[i].t, `note ${i} step`);
    assert.equal(midiOf(n.s, n.f), midiOf(truth[i].s, truth[i].f), `note ${i} pitch`);
    assert.ok(n.finger >= 0 && n.finger <= 4);
  });
});

test('held notes ring on to the next, long gaps stay rests', () => {
  const grid = quantize([
    { start: 0, duration: 0.3, midi: 64, amplitude: 1 },
    { start: 0.5, duration: 0.2, midi: 65, amplitude: 1 },
    { start: 4, duration: 0.2, midi: 67, amplitude: 1 },
  ], { bpm: 60, offset: 0, ticksPerBeat: 4 });
  assert.deepEqual(grid.map((n) => [n.tick, n.length]), [[0, 2], [2, 1], [16, 1]]);
});

test('tab: every pitch is playable and the hand stays in place', () => {
  // E4: open 1st string up to the 14th fret of the 4th (frets up to 15).
  assert.deepEqual(positions(64).map((p) => p.s), [1, 2, 3, 4]);
  // A scale run: small steps of the hand, no jumps across strings.
  const tab = assignTab([69, 71, 72, 74, 76]);
  for (let i = 1; i < tab.length; i++) {
    assert.ok(Math.abs(tab[i].f - tab[i - 1].f) <= 3, JSON.stringify(tab));
    assert.ok(Math.abs(tab[i].s - tab[i - 1].s) <= 1, JSON.stringify(tab));
  }
  // Below the guitar's range: moved up an octave.
  assert.equal(midiOf(assignTab([38])[0].s, assignTab([38])[0].f), 50);
});

test('fingers: one finger per fret, shifting only when needed', () => {
  assert.deepEqual(assignFingers([1, 2, 0, 3, 4]), [1, 2, 0, 3, 4]);
  assert.deepEqual(assignFingers([5, 6, 7, 8, 6, 5]), [1, 2, 3, 4, 2, 1]);
});

test('the JSON file is what the app reads, and reads back', () => {
  const text = toJson({ id: 'badak', title: 'Ba’dak Ala Bali', artist: 'فيروز', bpm: 90 },
    truth.map(({ t, s, f, d }) => ({ t, s, f, d })));
  assert.equal(text, readFileSync(new URL('../../assets/songs/badak.json', import.meta.url), 'utf8'));
  assert.equal(fromJson(text).notes.length, truth.length);
  assert.throws(() => fromJson('{"format":"x"}'), /yalla-song/);
  assert.throws(() => fromJson('{"format":"yalla-song/1","notes":[{"t":0,"s":9,"f":0,"d":1}]}'), /Ungültige/);
});

test('file names from titles', () => {
  assert.equal(slug('Ba’dak Ala Bali'), 'ba-dak-ala-bali');
  assert.equal(slug('تملي معاك'), 'song');
});
