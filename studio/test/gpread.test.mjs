import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { deflateRawSync } from 'node:zlib';
import { parseXml, playable, readGp, readGpif, songFromScore, unzip } from '../gpread.js';

const gpif = readFileSync(new URL('./score.gpif', import.meta.url), 'utf8');

/** A ZIP archive as Guitar Pro writes a .gp file: some entries stored, the score deflated. */
function zip(files) {
  const parts = [], central = [];
  let offset = 0;
  for (const [name, text, deflate] of files) {
    const raw = Buffer.from(text), data = deflate ? deflateRawSync(raw) : raw, nameBytes = Buffer.from(name);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(deflate ? 8 : 0, 8);
    local.writeUInt32LE(data.length, 18); local.writeUInt32LE(raw.length, 22); local.writeUInt16LE(nameBytes.length, 26);
    const entry = Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50, 0); entry.writeUInt16LE(deflate ? 8 : 0, 10);
    entry.writeUInt32LE(data.length, 20); entry.writeUInt32LE(raw.length, 24); entry.writeUInt16LE(nameBytes.length, 28);
    entry.writeUInt32LE(offset, 42);
    parts.push(local, nameBytes, data);
    central.push(entry, nameBytes);
    offset += 30 + nameBytes.length + data.length;
  }
  const dir = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(files.length, 8); end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(dir.length, 12); end.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...parts, dir, end]));
}

test('xml: elements, attributes, CDATA, entities, empty elements', () => {
  const doc = parseXml('<?xml version="1.0"?><a x="1 &amp; 2"><b><![CDATA[Tom & <Jerry>]]></b><c/><d k=\'v\'>x &lt; y</d></a>');
  const a = doc.children[0];
  assert.equal(a.attrs.x, '1 & 2');
  assert.deepEqual(a.children.map((c) => c.name), ['b', 'c', 'd']);
  assert.equal(a.children[0].text, 'Tom & <Jerry>');
  assert.equal(a.children[2].attrs.k, 'v');
  assert.equal(a.children[2].text, 'x < y');
});

test('a .gp file: the score inside the archive, deflated or stored', async () => {
  const bytes = zip([['VERSION', '7.0', false], ['Content/score.gpif', gpif, true], ['Content/Preferences.json', '{}', false]]);
  const archive = await unzip(bytes);
  assert.deepEqual(archive.names, ['VERSION', 'Content/score.gpif', 'Content/Preferences.json']);
  const score = await readGp(bytes);
  assert.equal(score.title, 'Jingle Bells');
  assert.equal(score.artist, 'Trad. & Co');
  await assert.rejects(readGp(zip([['VERSION', '7.0', false]])), /score\.gpif/);
  await assert.rejects(readGp(new Uint8Array(100)), /ZIP/);
});

test('the score: tempo, bars, tuning, notes in quarter notes', () => {
  const score = readGpif(gpif);
  assert.equal(score.bpm, 110);
  assert.equal(score.beatsPerBar, 4);
  assert.deepEqual(playable(score).map((t) => t.name), ['Steel Guitar']);
  const guitar = score.tracks[0];
  assert.deepEqual(guitar.tuning, [64, 59, 55, 50, 45, 40]);
  // E (chord C), dotted eighth G, sixteenth C with the index finger, D over A
  // held into the next bar, an eighth triplet; grace note, rest and muted note left out.
  assert.deepEqual(guitar.notes.map((n) => [+n.start.toFixed(3), +n.length.toFixed(3), n.midi, n.string, n.fret]), [
    [0, 1, 64, 1, 0], [1, 0.75, 67, 1, 3], [1.75, 0.25, 60, 2, 1], [2, 3, 62, 2, 3], [2, 2, 57, 3, 2],
    [5, 0.333, 64, 1, 0], [5.333, 0.333, 65, 1, 1], [5.667, 0.333, 67, 1, 3],
  ]);
  assert.equal(guitar.notes[2].finger, 1);
  assert.deepEqual(guitar.chords, [{ start: 0, name: 'C' }, { start: 6, name: 'G7' }]);
});

test('a track becomes a song: the tune, a grid that holds triplets, the chords', () => {
  const song = songFromScore(readGpif(gpif), 0);
  assert.deepEqual(song.meta, { id: 'jingle-bells', title: 'Jingle Bells', artist: 'Trad. & Co', bpm: 110, ticksPerBeat: 12, beatsPerBar: 4 });
  assert.equal(song.retuned, false);
  assert.deepEqual(song.notes.map(({ t, s, f, d }) => [t, s, f, d]), [
    [0, 1, 0, 12], [12, 1, 3, 9], [21, 2, 1, 3], [24, 2, 3, 36], [60, 1, 0, 4], [64, 1, 1, 4], [68, 1, 3, 4],
  ]);
  assert.deepEqual(song.notes.map((n) => n.finger), [null, null, 1, null, null, null, null]);
  assert.deepEqual(song.chords, [{ t: 0, d: 72, name: 'C' }, { t: 72, d: 24, name: 'G7' }]);
});

test('another tuning or a capo: the pitches are laid out anew in standard tuning', () => {
  const dropD = readGpif(gpif.replace('40 45 50 55 59 64', '38 45 50 55 59 64')
    .replace('<Property name="CapoFret"><Fret>0</Fret>', '<Property name="CapoFret"><Fret>2</Fret>'));
  const song = songFromScore(dropD, 0);
  assert.equal(song.retuned, true);
  const midi = song.notes.map((n) => [64, 59, 55, 50, 45, 40][n.s - 1] + n.f);
  // Pitches from the file's Midi numbers where given, else from tuning, capo and fret.
  assert.deepEqual(midi, [64, 67, 60, 62, 66, 67, 69]);
});
