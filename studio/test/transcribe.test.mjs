import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  CHORD_QUALITIES, assignFingers, assignTab, chartNotes, chordName, chordTones, detectTempo, fromJson, melodyOf,
  melodyTrack, midiOf, parseChord, positions, quantize, simplify, slug, suggestChords, toJson, transpose,
  transposeChord,
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

test('a realistic recording: reverb, noise, a player\'s timing', () => {
  const heard = read('./basic_pitch_realistic.json').notes
    .map(([start, duration, midi, amplitude]) => ({ start, duration, midi, amplitude }));
  const tempo = detectTempo(melodyOf(heard));
  assert.equal(tempo.bpm, 90);
  const notes = new Map(chartNotes(heard, tempo).map((n) => [n.t, n]));
  const right = truth.filter((n) => {
    const got = notes.get(n.t);
    return got && midiOf(got.s, got.f) === midiOf(n.s, n.f);
  }).length;
  assert.ok(right >= 55, `${right} of ${truth.length} notes right`);
});

test('a whole song: the melody is heard out of chords and bass', () => {
  const heard = read('./basic_pitch_full_song.json').notes
    .map(([start, duration, midi, amplitude]) => ({ start, duration, midi, amplitude }));
  const score = (mode) => {
    const tempo = detectTempo(mode === 'song' ? melodyTrack(heard) : melodyOf(heard));
    const chart = chartNotes(heard, { ...tempo, mode });
    const notes = new Map(chart.map((n) => [n.t, n]));
    const right = truth.filter((n) => {
      const got = notes.get(n.t);
      return got && midiOf(got.s, got.f) === midiOf(n.s, n.f);
    }).length;
    return { tempo, right, count: chart.length };
  };
  const song = score('song');
  assert.ok(Math.abs(song.tempo.bpm - 90) <= 0.3, `tempo ${song.tempo.bpm}`);
  assert.ok(song.right >= 46, `${song.right} of ${truth.length} notes right`);
  assert.ok(song.count <= 66, `${song.count} notes`);
  // One voice mode takes the accompaniment for the tune.
  assert.ok(score('single').right < 30);
});

test('a whole song mode on a guitar alone still finds the tune', () => {
  const tempo = detectTempo(melodyTrack(detected));
  assert.equal(tempo.bpm, 90);
  const notes = chartNotes(detected, { ...tempo, mode: 'song' });
  assert.ok(notes.length >= 55 && notes.length <= 57, `${notes.length} notes`);
});

test('simplify: grace notes go first, then short notes and repeats', () => {
  const grid = [
    { tick: 0, midi: 62, length: 3 },
    { tick: 3, midi: 66, length: 1 }, // grace note into the next
    { tick: 4, midi: 64, length: 4 },
    { tick: 8, midi: 65, length: 1 }, // a run of sixteenths stays at level 1
    { tick: 9, midi: 67, length: 1 },
    { tick: 10, midi: 69, length: 2 },
    { tick: 12, midi: 69, length: 4 }, // the same note again
  ];
  assert.deepEqual(simplify(grid, 0), grid);
  const ornamentsOff = simplify(grid, 1);
  assert.deepEqual(ornamentsOff.map((n) => n.tick), [0, 4, 8, 9, 10, 12]);
  assert.equal(ornamentsOff[0].length, 4, 'the note before takes up the time');
  const strong = simplify(grid, 2);
  assert.deepEqual(strong.map((n) => [n.tick, n.midi, n.length]), [[0, 62, 4], [4, 64, 6], [10, 69, 6]]);
  assert.deepEqual(grid[0].length, 3, 'the input stays as it was');
});

test('transpose: by semitones, folded by octaves into the guitar', () => {
  const grid = [{ tick: 0, midi: 40, length: 1 }, { tick: 1, midi: 76, length: 1 }];
  assert.deepEqual(transpose(grid, 2).map((n) => n.midi), [42, 78]);
  assert.deepEqual(transpose(grid, -3).map((n) => n.midi), [49, 73]);
  assert.deepEqual(transpose(grid, 5).map((n) => n.midi), [45, 69]);
  assert.equal(transposeChord('Dm', 2), 'Em');
  assert.equal(transposeChord('C/E', -1), 'B/Eb');
  assert.equal(transposeChord('A7', 3), 'C7');
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

test('chords: names, parts and the same table as the app', () => {
  assert.deepEqual(chordTones(parseChord('Dm')).sort((a, b) => a - b), [2, 5, 9]);
  assert.deepEqual(chordTones(parseChord('A7')).sort((a, b) => a - b), [1, 4, 7, 9]);
  const slash = parseChord('C/E');
  assert.equal(slash.root, 0);
  assert.equal(slash.bass, 4);
  for (const bad of ['H', 'Cx', 'c', '', 'Dmm', 'C/H']) assert.equal(parseChord(bad), null, bad);
  assert.equal(chordName(10, 'm7'), 'Bbm7');
  assert.equal(chordName(0, '', 4), 'C/E');
  assert.equal(chordName(0, '', 0), 'C');
  // The app reads the same chord types.
  const dart = readFileSync(new URL('../../lib/features/game/data/chord_symbol.dart', import.meta.url), 'utf8');
  const table = dart.slice(dart.indexOf('qualities ='), dart.indexOf('};', dart.indexOf('qualities =')));
  const fromDart = Object.fromEntries([...table.matchAll(/'([a-z0-9]*)': \[([0-9, ]+)\]/g)]
    .map((m) => [m[1], m[2].split(',').map(Number)]));
  assert.deepEqual(fromDart, Object.fromEntries(Object.entries(CHORD_QUALITIES)));
});

test('chords are suggested from the melody, as the app would choose them', () => {
  const chords = suggestChords(truth);
  assert.deepEqual(chords.slice(0, 3).map((c) => c.name), ['Dm', 'Am', 'C']);
  // Back to back, covering the song.
  for (let i = 1; i < chords.length; i++) assert.equal(chords[i].t, chords[i - 1].t + chords[i - 1].d);
});

test('chords go into the song file and come back', () => {
  const chords = [{ t: 0, d: 16, name: 'Dm' }, { t: 16, d: 8, name: 'C/E' }];
  const text = toJson({ id: 'x', title: 'X', bpm: 90 }, truth.slice(0, 2), chords);
  assert.match(text, /"chords": \[\n    \{"t": 0, "d": 16, "name": "Dm"\}/);
  assert.deepEqual(fromJson(text).chords, chords);
  assert.throws(() => fromJson(text.replace('"Dm"', '"Hm"')), /Ungültiger Akkord/);
});

