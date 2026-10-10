import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { ascii, gp5, keySignature, tabMeasures } from '../guitarpro.js';

const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url)));
const bytes = (path) => new Uint8Array(readFileSync(new URL(path, import.meta.url)));
const badak = read('../../assets/songs/badak.json');
const cases = read('./tab_cases.json');
// 64ths per note value.
const units = (b) => (64 / b.value) * (b.dotted ? 1.5 : 1);

// The reference files are written by PyGuitarPro 0.10 from the same song,
// so every byte is as the Guitar Pro 5.10 format has it.
test('the .gp5 file is byte for byte the reference', () => {
  assert.deepEqual(gp5(badak, badak.notes), bytes('./badak.gp5'));
  assert.deepEqual(gp5(cases, cases.notes, cases.chords), bytes('./tab_cases.gp5'));
});

test('every bar is full, notes keep their place, string and fret', () => {
  for (const song of [badak, cases]) {
    const measures = tabMeasures(song);
    const bar = song.beatsPerBar * 16;
    measures.forEach((m, i) => assert.equal(m.beats.reduce((a, b) => a + units(b), 0), bar, `bar ${i + 1}`));
    const struck = [];
    let at = 0;
    for (const m of measures) {
      for (const b of m.beats) {
        for (const n of b.notes) if (!n.tie) struck.push([at / 4, n.s, n.f]);
        at += units(b);
      }
    }
    const want = song.notes.map((n) => [n.t, n.s, n.f]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    assert.deepEqual(struck.sort((a, b) => a[0] - b[0] || a[1] - b[1]), want);
  }
});

test('held notes go on tied, silence is a rest, chords sit on their beat', () => {
  const measures = tabMeasures({
    notes: [{ t: 0, s: 2, f: 1, d: 6, finger: 1 }, { t: 2, s: 1, f: 3, d: 1, finger: 3 }],
    chords: [{ t: 4, d: 4, name: 'F' }],
    ticksPerBeat: 4, beatsPerBar: 2,
  });
  const beats = measures[0].beats.map((b) => [b.value, b.dotted, b.rest, b.text ?? '',
    b.notes.map((n) => `${n.s}:${n.f}${n.tie ? '~' : ''}${n.finger ?? ''}`).sort().join(' ')]);
  assert.deepEqual(beats, [
    [8, false, false, '', '2:11'],
    [16, false, false, '', '1:33 2:1~'],
    [16, false, false, '', '2:1~'],
    [8, false, false, 'F', '2:1~'],
    [8, false, true, '', ''],
  ]);
});

test('the key signature spells the notes as the song does', () => {
  // Badak: D minor, one flat (B flat, not A sharp).
  assert.deepEqual(keySignature(badak.notes), { fifths: -1, minor: true });
  // A G major scale: one sharp.
  const g = [[3, 0], [3, 2], [2, 0], [2, 1], [2, 3], [1, 0], [1, 2], [1, 3]].map(([s, f], t) => ({ t, s, f, d: 1 }));
  assert.deepEqual(keySignature(g), { fifths: 1, minor: false });
  assert.deepEqual(keySignature([]), { fifths: 0, minor: false });
});

test('titles are written in plain letters', () => {
  assert.equal(ascii('Ba’dak – Grüße'), "Ba'dak - Gruesse");
  assert.equal(ascii('فيروز'), 'Fyrwz');
  assert.equal(ascii('Café ☺'), 'Cafe ?');
});
