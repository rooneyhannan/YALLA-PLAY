// Yalla Studio: reads a Guitar Pro 7/8 file (.gp) into a song. A .gp file is
// a ZIP archive whose Content/score.gpif is XML: the tracks with their
// tuning, the bars, voices, beats, notes and rhythms, each in its own list
// and referring to the others by id. Pure functions (the ZIP is inflated
// with the platform's DecompressionStream), so they run under `node --test`.
import { OPEN_STRINGS, assignTab, parseChord, slug } from './transcribe.js';

// ---------------------------------------------------------------- ZIP

/** The files in a ZIP archive: name → bytes (inflated). */
export async function unzip(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let end = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (view.getUint32(i, true) === 0x06054b50) { end = i; break; }
  }
  if (end < 0) throw new Error('Das ist keine Guitar-Pro-Datei (.gp) – kein ZIP-Archiv.');
  const count = view.getUint16(end + 10, true);
  let at = view.getUint32(end + 16, true);
  const files = new Map();
  for (let n = 0; n < count; n++) {
    if (view.getUint32(at, true) !== 0x02014b50) break;
    const method = view.getUint16(at + 10, true);
    const size = view.getUint32(at + 20, true);
    const nameLength = view.getUint16(at + 28, true);
    const extra = view.getUint16(at + 30, true), comment = view.getUint16(at + 32, true);
    const local = view.getUint32(at + 42, true);
    const name = new TextDecoder().decode(bytes.subarray(at + 46, at + 46 + nameLength));
    const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
    files.set(name, { method, data: bytes.subarray(start, start + size) });
    at += 46 + nameLength + extra + comment;
  }
  return {
    names: [...files.keys()],
    async read(name) {
      const file = files.get(name);
      if (!file) return null;
      if (file.method === 0) return file.data;
      if (file.method !== 8) throw new Error(`Unbekannte Kompression ${file.method} in ${name}`);
      const stream = new Blob([file.data]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
      return new Uint8Array(await new Response(stream).arrayBuffer());
    },
  };
}

// ---------------------------------------------------------------- XML

const ENTITIES = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'" };
const unescape = (text) => text.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (all, e) =>
  e[0] === '#' ? String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : +e.slice(1))
    : ENTITIES[e] ?? all);

/** A small XML reader: elements {name, attrs, children, text}. */
export function parseXml(text) {
  const root = { name: '#root', attrs: {}, children: [], text: '' };
  const stack = [root];
  // 1 CDATA · 2 "/" of a closing tag · 3 name · 4 attributes · 5 "/" of an empty element · 6 text
  const token = /<!\[CDATA\[([\s\S]*?)\]\]>|<!--[\s\S]*?-->|<[?!][^>]*>|<(\/?)([^\s/>]+)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>|([^<]+)/g;
  for (let m; (m = token.exec(text));) {
    const top = stack[stack.length - 1];
    if (m[1] != null) top.text += m[1];
    else if (m[6] != null) top.text += unescape(m[6]);
    else if (m[3] != null) {
      if (m[2]) {
        if (stack.length > 1) stack.pop();
        continue;
      }
      const attrs = {};
      for (const a of m[4].matchAll(/([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) attrs[a[1]] = unescape(a[2] ?? a[3]);
      const node = { name: m[3], attrs, children: [], text: '' };
      top.children.push(node);
      if (!m[5]) stack.push(node);
    }
  }
  return root;
}
const child = (node, name) => node?.children.find((c) => c.name === name);
const children = (node, name) => node?.children.filter((c) => c.name === name) ?? [];
const text = (node) => (node?.text ?? '').trim();
const ids = (node) => text(node).split(/\s+/).filter(Boolean).map(Number);
/** Every element of this name anywhere below. */
function* all(node, name) {
  for (const c of node.children) {
    if (c.name === name) yield c;
    yield* all(c, name);
  }
}
const property = (node, name) => [...all(node, 'Property')].find((p) => p.attrs.name === name);

// ---------------------------------------------------------------- score

/** Times in quarter notes, rounded so that three triplet thirds make a whole. */
const exact = (x) => Math.round(x * 1e6) / 1e6;

const NOTE_VALUES = {
  Whole: 4, Half: 2, Quarter: 1, Eighth: 1 / 2, '16th': 1 / 4, '32nd': 1 / 8, '64th': 1 / 16, '128th': 1 / 32, '256th': 1 / 64,
};
const FINGERS = { P: null, T: null, I: 1, M: 2, A: 3, C: 4 };

/**
 * The score in a .gp file: {title, artist, bpm, beatsPerBar, beatUnit,
 * tracks: [{name, tuning (MIDI, string 1 = highest), capo, notes, chords}]}.
 * Times are in quarter notes from the start, read bar by bar as written
 * (repeats are not unfolded). Notes: {start, length, string, fret, midi,
 * finger}; a tied note lengthens the one before on its string.
 */
export async function readGp(bytes) {
  const zip = await unzip(bytes);
  const xml = await zip.read('Content/score.gpif');
  if (!xml) throw new Error('In der Datei fehlt die Partitur (Content/score.gpif). Ist es eine Guitar-Pro-7/8-Datei?');
  return readGpif(new TextDecoder().decode(xml));
}

export function readGpif(source) {
  const doc = child(parseXml(source), 'GPIF');
  if (!doc) throw new Error('Unbekanntes Partitur-Format.');
  const byId = (list, name) => new Map(children(child(doc, list), name).map((n) => [n.attrs.id, n]));
  const bars = byId('Bars', 'Bar'), voices = byId('Voices', 'Voice'), beats = byId('Beats', 'Beat');
  const notes = byId('Notes', 'Note'), rhythms = byId('Rhythms', 'Rhythm');
  const score = child(doc, 'Score');

  let bpm = 120;
  for (const a of all(child(doc, 'MasterTrack') ?? { children: [] }, 'Automation')) {
    if (text(child(a, 'Type')) === 'Tempo' && +text(child(a, 'Bar') ?? { text: '0' }) === 0) {
      const [value, unit] = text(child(a, 'Value')).split(/\s+/).map(Number);
      // The unit: 1 eighth, 2 quarter, 3 dotted quarter, 4 half, 5 dotted half.
      const quarters = { 1: 0.5, 2: 1, 3: 1.5, 4: 2, 5: 3 }[unit] ?? 1;
      if (value > 0) bpm = value * quarters;
      break;
    }
  }

  const masterBars = children(child(doc, 'MasterBars'), 'MasterBar');
  const [num, den] = (text(child(masterBars[0], 'Time')) || '4/4').split('/').map(Number);

  const trackNodes = children(child(doc, 'Tracks'), 'Track');
  const tracks = trackNodes.map((track, index) => {
    const tuningNode = property(track, 'Tuning');
    const pitches = tuningNode ? ids(child(tuningNode, 'Pitches')) : [];
    const capo = +text(child(property(track, 'CapoFret'), 'Fret')) || 0;
    const diagrams = new Map();
    const collection = property(track, 'DiagramCollection') ?? property(track, 'ChordCollection');
    for (const item of collection ? all(collection, 'Item') : []) diagrams.set(item.attrs.id, item.attrs.name);
    const out = { name: text(child(track, 'Name')) || `Spur ${index + 1}`, tuning: [...pitches].reverse(), capo, notes: [], chords: [] };
    let barStart = 0;
    const ringing = new Map(); // string → note still to be tied to
    for (const master of masterBars) {
      const [n, d] = (text(child(master, 'Time')) || `${num}/${den}`).split('/').map(Number);
      const barId = String(ids(child(master, 'Bars'))[index]);
      const bar = bars.get(barId);
      for (const voiceId of bar ? ids(child(bar, 'Voices')) : []) {
        if (voiceId < 0) continue;
        let at = barStart;
        for (const beatId of ids(child(voices.get(String(voiceId)), 'Beats'))) {
          const beat = beats.get(String(beatId));
          if (!beat) continue;
          // Grace notes take no time of their own; they are left out.
          if (child(beat, 'GraceNotes')) continue;
          const length = beatLength(rhythms.get(child(beat, 'Rhythm')?.attrs.ref));
          const chordId = text(child(beat, 'Chord'));
          if (chordId && diagrams.has(chordId)) out.chords.push({ start: exact(at), name: diagrams.get(chordId) });
          for (const noteId of ids(child(beat, 'Notes'))) {
            const note = notes.get(String(noteId));
            if (!note) continue;
            if (property(note, 'Muted') || property(note, 'DeadNote')) continue;
            const string = +text(child(property(note, 'String'), 'String'));
            const fret = +text(child(property(note, 'Fret'), 'Fret'));
            const midiProp = text(child(property(note, 'Midi'), 'Number'));
            const midi = midiProp !== '' ? +midiProp : (pitches[string] ?? 40) + capo + fret;
            const tie = child(note, 'Tie');
            const before = ringing.get(string);
            if (tie?.attrs.destination === 'true' && before) {
              before.length = exact(at + length - before.start);
              continue;
            }
            const finger = FINGERS[text(child(note, 'LeftFingering'))] ?? null;
            const entry = { start: exact(at), length: exact(length), string: pitches.length - string, fret, midi, finger };
            out.notes.push(entry);
            ringing.set(string, entry);
          }
          at += length;
        }
      }
      barStart += (n * 4) / d;
    }
    out.notes.sort((a, b) => a.start - b.start || a.string - b.string);
    out.chords.sort((a, b) => a.start - b.start);
    out.end = barStart;
    return out;
  });

  return {
    title: text(child(score, 'Title')), artist: text(child(score, 'Artist')),
    bpm: Math.round(bpm * 10) / 10, beatsPerBar: num, beatUnit: den, tracks,
  };
}

/** A rhythm's length in quarter notes: value, dots, tuplet. */
function beatLength(rhythm) {
  if (!rhythm) return 1;
  let length = NOTE_VALUES[text(child(rhythm, 'NoteValue'))] ?? 1;
  const dots = +(child(rhythm, 'AugmentationDot')?.attrs.count ?? 0);
  length *= 2 - 0.5 ** dots;
  for (const name of ['PrimaryTuplet', 'SecondaryTuplet']) {
    const t = child(rhythm, name);
    if (t && +t.attrs.num > 0 && +t.attrs.den > 0) length *= +t.attrs.den / +t.attrs.num;
  }
  return length;
}

// ---------------------------------------------------------------- song

/** Tracks a guitar plays: with strings, not drums. */
export const playable = (score) => score.tracks
  .map((t, index) => ({ ...t, index }))
  .filter((t) => t.tuning.length >= 4 && t.notes.length);

/**
 * One track of the score as a Yalla song: {meta, notes, chords}. The tune
 * is the highest note of each beat (the app plays one note at a time). In
 * standard tuning without capo the file's strings and frets stay; otherwise
 * the pitches are laid out anew for standard tuning. The grid is the
 * coarsest that holds every note: sixteenths, or finer for triplets.
 */
export function songFromScore(score, trackIndex) {
  const track = score.tracks[trackIndex];
  const melody = [];
  for (const n of track.notes) {
    const last = melody[melody.length - 1];
    if (last && Math.abs(last.start - n.start) < 1e-6) {
      if (n.midi > last.midi) melody[melody.length - 1] = n;
    } else melody.push(n);
  }
  // One note at a time: a note ends where the next one starts.
  melody.forEach((n, i) => {
    const next = melody[i + 1];
    if (next && n.start + n.length > next.start) n.length = next.start - n.start;
  });

  const times = [...melody.flatMap((n) => [n.start, n.length]), ...track.chords.map((c) => c.start)];
  const ticksPerBeat = [4, 12, 8, 24, 16, 48].find((q) => times.every((x) => Math.abs(x * q - Math.round(x * q)) < 1e-3)) ?? 48;
  const tick = (x) => Math.round(x * ticksPerBeat);

  const standard = track.capo === 0 && track.tuning.length === 6 && track.tuning.every((p, i) => p === OPEN_STRINGS[i]);
  const placed = standard
    ? melody.map((n) => ({ s: n.string, f: n.fret }))
    : assignTab(melody.map((n) => n.midi));
  // Fingers the file gives stay; the Studio works out the others.
  const notes = melody.map((n, i) => ({
    t: tick(n.start), s: placed[i].s, f: placed[i].f, d: Math.max(1, tick(n.length)),
    finger: standard && n.finger != null ? n.finger : null,
  }));

  const end = Math.max(track.end ?? 0, ...melody.map((n) => n.start + n.length));
  const chords = [];
  track.chords.forEach((c, i) => {
    const name = c.name.replace(/\s+/g, '');
    if (!parseChord(name)) return;
    const until = track.chords[i + 1]?.start ?? end;
    if (until > c.start) chords.push({ t: tick(c.start), d: tick(until) - tick(c.start), name });
  });

  // Bars in quarter notes; 6/8 becomes three beats of a dotted … quarter count.
  const beatsPerBar = (score.beatsPerBar * 4) / score.beatUnit;
  const title = score.title || track.name;
  return {
    meta: {
      id: slug(title), title, artist: score.artist, bpm: score.bpm, ticksPerBeat,
      beatsPerBar: Number.isInteger(beatsPerBar) && beatsPerBar > 0 ? beatsPerBar : 4,
    },
    notes, chords,
    retuned: !standard,
  };
}
