import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  appSongIds, backingOf,
  CHORD_QUALITIES, assignFingers, assignTab, fingerTab, chartNotes, chordName, chordTones, detectTempo, fromJson, melodyOf,
  findKey, findMaqam, melodyTrack, midiOf, onsetEnergy, parseChord, positions, quantize, simplify, slug, suggestChords, toJson, transpose,
  transposeChord, withAttacks,
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

test('a microphone: the guitar body booming is no note', () => {
  const heard = read('./basic_pitch_body_boom.json').notes
    .map(([start, duration, midi, amplitude]) => ({ start, duration, midi, amplitude }));
  // Jingle Bells, played on the two highest strings only.
  const E = 64, F = 65, G = 67, C = 60, D = 62;
  const tune = [E, E, E, E, E, E, E, G, C, D, E, F, F, F, F, F, E, E, E, E, E, D, D, E, D, G];
  const melody = melodyOf(heard).map((n) => n.midi);
  assert.ok(melody.every((m) => m >= C), `low notes in ${melody}`);
  assert.deepEqual([...new Set(melody)].sort(), [...new Set(tune)].sort());
  assert.ok(melody.length >= tune.length && melody.length <= tune.length + 4, `${melody.length} notes`);
  const notes = chartNotes(heard, detectTempo(melodyOf(heard)));
  assert.ok(notes.every((n) => n.s <= 2), 'only the two highest strings');
});

test('a pluck is told from a string swelling as it rings', () => {
  const rate = 22050, samples = new Float32Array(rate * 2);
  for (let i = 0; i < samples.length; i++) {
    const t = i / rate;
    // A note ringing and slowly swelling, plucked again at 1.5 s.
    samples[i] = 0.2 * (1 + 0.8 * Math.sin(2 * Math.PI * 1.5 * t)) * Math.sin(2 * Math.PI * 330 * t) +
      (t >= 1.5 ? 0.5 * Math.exp(-(t - 1.5) * 30) * Math.sin(2 * Math.PI * 3000 * t) : 0);
  }
  const [swell, pluck] = withAttacks([{ start: 0.85 }, { start: 1.55 }], onsetEnergy(samples, rate));
  assert.ok(swell.attack < 5, `swell ${swell.attack} dB`);
  assert.ok(pluck.attack > 7, `pluck ${pluck.attack} dB`);
});

test('a long note ringing on is one note, however often it seems to start', () => {
  const heard = read('./basic_pitch_long_notes.json').notes
    .map(([start, duration, midi, amplitude, attack]) => ({ start, duration, midi, amplitude, attack }));
  const E = 64, G = 67, C = 60, D = 62;
  assert.deepEqual(melodyOf(heard).map((n) => n.midi), [E, E, E, G, G, E, E, E, E, C, D, D, E, G]);
  const notes = chartNotes(heard, detectTempo(melodyOf(heard)));
  assert.deepEqual(notes.slice(0, 13).map((n) => n.d), [4, 4, 24, 4, 4, 4, 4, 4, 4, 24, 4, 4, 16]);
  // Without the attacks measured, the ringing notes come back.
  assert.ok(melodyOf(heard.map(({ attack, ...n }) => n)).length > 18);
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

/** Hand positions (index finger's fret) of the fretted notes, in order. */
const handOf = (frets, fingers) => frets.flatMap((f, i) => (f ? [{ i, f, p: f - fingers[i] + 1 }] : []));

/**
 * Rooney's rule, checked between every two fretted notes: every shift with
 * the same finger. Returns the shifts and which finger slid at each.
 */
function checkShifts(frets, fingers, label = '') {
  const slides = [];
  const hand = handOf(frets, fingers);
  frets.forEach((f, i) => { if (!f) assert.equal(fingers[i], 0, `${label} note ${i}: open string`); });
  for (let k = 0; k < hand.length; k++) {
    const b = hand[k];
    assert.ok(fingers[b.i] >= 1 && fingers[b.i] <= 4, `${label} note ${b.i}: finger ${fingers[b.i]}`);
    if (!k || b.p === hand[k - 1].p) continue;
    const a = hand[k - 1];
    assert.equal(fingers[b.i], fingers[a.i],
      `${label} note ${b.i}: fret ${a.f} finger ${fingers[a.i]} → fret ${b.f} finger ${fingers[b.i]}`);
    slides.push(fingers[b.i]);
  }
  return { shifts: slides.length, pinky: slides.filter((f) => f === 4).length, slides };
}

/** What the shifts weigh: a pinky shift counts one and a half. */
const weight = ({ shifts, pinky }) => shifts + pinky / 2;

/** The least weight of shifts that keeps the rule, worked out on its own. */
function fewestShifts(frets) {
  const fretted = frets.filter((f) => f > 0);
  if (!fretted.length) return 0;
  // Hand position and finger of the last note → least weight.
  let best = new Map();
  for (let k = 1; k <= 4; k++) if (fretted[0] - k + 1 >= 1) best.set(`${fretted[0] - k + 1},${k}`, 0);
  for (let i = 1; i < fretted.length; i++) {
    const next = new Map();
    for (const [key, n] of best) {
      const [q, last] = key.split(',').map(Number);
      for (let k = 1; k <= 4; k++) {
        const p = fretted[i] - k + 1;
        if (p < 1 || (p !== q && k !== last)) continue;
        const c = n + (p === q ? 0 : k === 4 ? 1.5 : 1);
        const to = `${p},${k}`;
        if (!next.has(to) || c < next.get(to)) next.set(to, c);
      }
    }
    best = next;
  }
  return Math.min(...best.values());
}

test('fingers: every shift with the same finger, index first', () => {
  // Up from fret 3 to 5: the index slides along, not 1 → 3.
  const lamma = [3, 5, 6, 8, 6, 6, 5, 5, 3, 3, 2, 3];
  assert.deepEqual(assignFingers(lamma), [1, 1, 2, 4, 2, 2, 1, 1, 1, 1, 1, 2]);
  assert.deepEqual(checkShifts(lamma, assignFingers(lamma)).slides, [1, 1, 1]);
  // Down from fret 8 to 3: the pinky cannot slide there, so the index
  // slides 5 → 6 and the ring finger 8 → 3.
  assert.deepEqual(assignFingers([5, 6, 7, 8, 3]), [1, 1, 2, 3, 3]);
  // Up fret by fret: the index slides, never the pinky.
  const run = [1, 2, 3, 4, 5, 6];
  assert.deepEqual(assignFingers(run), [1, 1, 1, 2, 3, 4]);
  assert.equal(checkShifts(run, assignFingers(run)).pinky, 0);
  // Fret 1–3, then 5–6: the index could only slide with a second shift,
  // the ring finger slides with one (3 → 5).
  assert.deepEqual(assignFingers([1, 2, 3, 5, 6]), [1, 2, 3, 3, 4]);
  // Index rather than pinky: 1 and 2 with the index, then 4 and 5.
  assert.deepEqual(assignFingers([1, 2, 4, 5]), [1, 1, 3, 4]);
});

test('fingers: the pinky slides only where it saves a shift', () => {
  // Frets 1–5: the index slides once (1 → 2), not the pinky (4 → 5).
  const up = [1, 2, 3, 4, 5];
  assert.deepEqual(assignFingers(up), [1, 1, 2, 3, 4]);
  assert.deepEqual(checkShifts(up, assignFingers(up)).slides, [1]);
  // 1, 2, 4, then a jump to 8: the pinky slides 4 → 8 in one shift; any
  // other finger needs two.
  assert.deepEqual(assignFingers([1, 2, 4, 8]), [1, 2, 4, 4]);
  // A long run up a string: one index shift per step, never the pinky.
  const run = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  const got = checkShifts(run, assignFingers(run));
  assert.equal(got.pinky, 0);
  assert.equal(weight(got), fewestShifts(run));
});

test('fingers: the songs keep the rules with the fewest shifts and no pinky shift', () => {
  for (const id of ['badak', 'lamma-bada']) {
    const frets = read(`../../assets/songs/${id}.json`).notes.sort((a, b) => a.t - b.t).map((n) => n.f);
    const got = checkShifts(frets, assignFingers(frets), id);
    assert.equal(weight(got), fewestShifts(frets), id);
    assert.equal(got.pinky, 0, id);
  }
});

const randomTunes = (count) => {
  let seed = 7;
  const random = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const tunes = [];
  for (let n = 0; n < count; n++) {
    let f = 1 + Math.floor(random() * 12);
    const frets = [];
    const length = 4 + Math.floor(random() * 30);
    for (let i = 0; i < length; i++) {
      if (random() < 0.15) { frets.push(0); continue; }
      f = Math.min(20, Math.max(1, f + Math.round((random() - 0.5) * 10)));
      frets.push(f);
    }
    tunes.push(frets);
  }
  return tunes;
};

test('fingers: random tunes keep the rules with the fewest shifts', () => {
  for (const frets of randomTunes(300)) {
    assert.equal(weight(checkShifts(frets, assignFingers(frets), frets.join(','))), fewestShifts(frets), frets.join(','));
  }
});

test('tab and fingers: a note moves to another string when that saves a shift', () => {
  // G4 on the 1st string, 3rd fret, among notes high on the 2nd string:
  // played on the 2nd string, 8th fret, the hand stays in place.
  const notes = [{ s: 2, f: 9 }, { s: 2, f: 10 }, { s: 1, f: 3 }, { s: 2, f: 9 }, { s: 2, f: 10 }];
  const tab = fingerTab(notes);
  assert.deepEqual(tab.map((n) => [n.s, n.f, n.finger]), [[2, 9, 3], [2, 10, 4], [2, 8, 2], [2, 9, 3], [2, 10, 4]]);
  assert.equal(checkShifts(tab.map((n) => n.f), tab.map((n) => n.finger)).shifts, 0);
  // Nothing to gain: every note keeps its string.
  const easy = [{ s: 1, f: 1 }, { s: 1, f: 3 }, { s: 2, f: 1 }, { s: 1, f: 0 }];
  assert.deepEqual(fingerTab(easy).map((n) => [n.s, n.f, n.finger]), [[1, 1, 1], [1, 3, 3], [2, 1, 1], [1, 0, 0]]);
});

test('tab and fingers: same pitches, the rules kept, never more shifts than the tab alone', () => {
  for (const frets of randomTunes(150)) {
    const notes = frets.map((f) => ({ s: 1, f: Math.min(f, 15) }));
    const tab = fingerTab(notes);
    tab.forEach((n, i) => assert.equal(midiOf(n.s, n.f), midiOf(notes[i].s, notes[i].f)));
    const got = checkShifts(tab.map((n) => n.f), tab.map((n) => n.finger), frets.join(','));
    assert.ok(weight(got) <= fewestShifts(notes.map((n) => n.f)), frets.join(','));
    assert.equal(weight(got), fewestShifts(tab.map((n) => n.f)), frets.join(','));
  }
});

test('tab and fingers: the songs are tabbed so that no string change saves a shift', () => {
  for (const id of ['badak', 'lamma-bada']) {
    const notes = read(`../../assets/songs/${id}.json`).notes.sort((a, b) => a.t - b.t);
    const tab = fingerTab(notes);
    assert.deepEqual(tab.map((n) => [n.s, n.f]), notes.map((n) => [n.s, n.f]), id);
    assert.deepEqual(tab.map((n) => n.finger), assignFingers(notes.map((n) => n.f)), id);
  }
});

test('the recording becomes notes whose shifts keep the rules', () => {
  const notes = chartNotes(detected, detectTempo(melodyOf(detected)));
  const got = checkShifts(notes.map((n) => n.f), notes.map((n) => n.finger));
  assert.equal(got.pinky, 0);
});

test('the JSON file is what the app reads, and reads back', () => {
  const file = readFileSync(new URL('../../assets/songs/badak.json', import.meta.url), 'utf8');
  const text = toJson({ id: 'badak', title: 'Ba’dak Ala Bali', artist: 'فيروز', bpm: 90 },
    truth.map(({ t, s, f, d }) => ({ t, s, f, d })), fromJson(file).chords, fromJson(file).backing);
  assert.equal(text, file);
  assert.equal(fromJson(text).notes.length, truth.length);
  assert.equal(fromJson(text).chords.at(-1).name, 'Dm');
  assert.throws(() => fromJson('{"format":"x"}'), /yalla-song/);
  assert.throws(() => fromJson('{"format":"yalla-song/1","notes":[{"t":0,"s":9,"f":0,"d":1}]}'), /Ungültige/);
});

test('the backing the app plays is saved with the song and read back', () => {
  const notes = [{ t: 0, s: 1, f: 0, d: 2 }];
  const plain = toJson({ id: 'x', title: 'X', bpm: 90 }, notes);
  assert.equal(JSON.parse(plain).backing, undefined);
  assert.deepEqual(backingOf(fromJson(plain).backing), { guitar: 'both', rhythm: 'auto', darbuka: true });
  const text = toJson({ id: 'x', title: 'X', bpm: 90 }, notes, [], { guitar: 'strum', rhythm: 'baladi', darbuka: false });
  assert.deepEqual(JSON.parse(text).backing, { guitar: 'strum', rhythm: 'baladi', darbuka: false });
  assert.deepEqual(backingOf(fromJson(text).backing), { guitar: 'strum', rhythm: 'baladi', darbuka: false });
  assert.deepEqual(backingOf({ rhythm: 'saidi' }), { guitar: 'both', rhythm: 'saidi', darbuka: true });
  assert.throws(() => fromJson(text.replace('baladi', 'polka')), /Begleitung/);
  assert.throws(() => backingOf({ darbuka: 'ja' }), /Begleitung/);
  // The app's songs carry theirs.
  for (const id of ['badak', 'lamma-bada']) {
    const song = fromJson(readFileSync(new URL(`../../assets/songs/${id}.json`, import.meta.url), 'utf8'));
    assert.ok(song.backing, id);
  }
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

test('chords are suggested from the melody\'s maqam', () => {
  // Ba’dak ends on D: heard in D minor, one chord per bar at most.
  assert.deepEqual(findKey(truth), { tonic: 2, minor: true });
  const chords = suggestChords(truth);
  assert.deepEqual(chords.slice(0, 3).map((c) => c.name), ['Dm', 'F', 'Gm']);
  for (const c of chords) assert.equal(c.d % 16, 0);
  // Back to back, covering the song.
  for (let i = 1; i < chords.length; i++) assert.equal(chords[i].t, chords[i - 1].t + chords[i - 1].d);
});

test('the maqam is found from the melody and its final note', () => {
  assert.deepEqual(findMaqam(truth), { tonic: 2, maqam: 'nahawand', name: 'D Nahawand' });
  // A melody from MIDI pitches on the G string, a beat each, the last one long.
  const melody = (pitches) => pitches.map((p, i) => ({ t: 4 * i, s: 3, f: p - 55, d: i === pitches.length - 1 ? 8 : 4 }));
  const D = 62;
  const cases = [
    // Hijaz on D: E flat and F sharp.
    [[D, D + 1, D + 4, D + 5, D + 7, D + 5, D + 4, D + 1, D + 4, D + 1, D], 'D Hijaz'],
    // Kurd on D: E flat and F.
    [[D, D + 1, D + 3, D + 5, D + 7, D + 5, D + 3, D + 1, D + 3, D + 1, D], 'D Kurd'],
    // The same notes as Bb Ajam and G Nahawand; the melody rests on D.
    [[D, D + 3, D + 1, D, D + 5, D + 3, D + 1, D], 'D Kurd'],
    // C Ajam, ending on C.
    [[60, 62, 64, 65, 67, 69, 71, 72, 67, 64, 62, 60], 'C Ajam'],
    // A Nahawand with its raised seventh going up to A.
    [[57, 59, 60, 62, 64, 65, 68, 69, 64, 60, 59, 57], 'A Nahawand'],
  ];
  for (const [pitches, name] of cases) assert.equal(findMaqam(melody(pitches)).name, name, name);
  // A short stray note heard at the end does not move the tonic.
  const ajam = melody([60, 62, 64, 65, 67, 69, 71, 72, 67, 64, 62, 60]);
  ajam.push({ t: ajam.at(-1).t + 8, s: 3, f: 64 - 55, d: 2 });
  assert.equal(findMaqam(ajam).name, 'C Ajam');
  // Hijaz gets its own chords: D major on the tonic, E flat above it.
  const hijaz = melody([D, D + 1, D + 4, D + 5, D + 7, D + 8, D + 10, D + 7, D + 5, D + 4, D + 1, D + 1, D + 3, D + 1, D + 4, D]);
  const names = new Set(suggestChords(hijaz).map((c) => c.name));
  assert.ok(names.has('D') && !names.has('Dm'), [...names].join(' '));
  for (const n of names) assert.ok(['D', 'Eb', 'Gm', 'Cm'].includes(n), n);
});

test('chords go into the song file and come back', () => {
  const chords = [{ t: 0, d: 16, name: 'Dm' }, { t: 16, d: 8, name: 'C/E' }];
  const text = toJson({ id: 'x', title: 'X', bpm: 90 }, truth.slice(0, 2), chords);
  assert.match(text, /"chords": \[\n    \{"t": 0, "d": 16, "name": "Dm"\}/);
  assert.deepEqual(fromJson(text).chords, chords);
  assert.throws(() => fromJson(text.replace('"Dm"', '"Hm"')), /Ungültiger Akkord/);
  // The maqam goes along when known.
  const withMaqam = toJson({ id: 'x', title: 'X', bpm: 90, maqam: 'D Nahawand' }, truth.slice(0, 2));
  assert.equal(fromJson(withMaqam).maqam, 'D Nahawand');
  assert.ok(!('maqam' in fromJson(text)));
});

test('the app\'s songs are read from the web build\'s asset manifest', () => {
  const manifest = readFileSync(new URL('../../assets/AssetManifest.bin.json', import.meta.url), 'utf8');
  assert.ok(appSongIds(manifest).includes('badak'));
  // Paths stand in the binary manifest after a length byte.
  const binary = '\r\x01\x17assets/songs/badak.json\x0c\x01\x16assets/songs/my-2.json\x19assets/design/s1_1.png';
  assert.deepEqual(appSongIds(JSON.stringify(btoa(binary))), ['badak', 'my-2']);
});
