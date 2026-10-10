// Yalla Studio: a song as a Guitar Pro 5 file (.gp5), which Guitar Pro 5–8,
// TuxGuitar, MuseScore and Songsterr open. Field by field as PyGuitarPro
// writes version 5.10; pure functions, so they run under `node --test` too.
import { findKey, midiOf } from './transcribe.js';

/** Standard tuning, string 1 = high E … 6 = low E, as MIDI notes. */
const TUNING = [64, 59, 55, 50, 45, 40];
/** Quarter note in the file's smallest step, a 64th. */
const QUARTER = 16;

/**
 * Lays a song out in bars of beats as a tab needs it. A beat lasts until
 * the next note starts or ends, a chord starts or the bar ends; notes still
 * sounding go on as tied notes, silence becomes rests. Each beat has a
 * length a tab can show (whole … 64th, dotted), longer ones become several.
 * Returns [{beats: [{value, dotted, rest, text, notes: [{s, f, tie, finger}]}]}],
 * value 1 = whole, 4 = quarter, 16 = 16th.
 */
export function tabMeasures({ notes, chords = [], ticksPerBeat = 4, beatsPerBar = 4 }) {
  const at = (tick) => Math.round((tick * QUARTER) / ticksPerBeat);
  // A string plays one note at a time: the next note on it cuts the one before.
  const sounding = [...notes]
    .map((n) => ({ s: n.s, f: n.f, finger: n.finger, from: at(n.t), to: at(n.t + n.d) }))
    .filter((n) => n.to > n.from)
    .sort((a, b) => a.from - b.from || a.s - b.s);
  for (const n of sounding) {
    const next = sounding.find((m) => m !== n && m.s === n.s && m.from >= n.from && m.from < n.to);
    if (next) n.to = next.from;
  }
  const notesOn = sounding.filter((n) => n.to > n.from);
  const marks = chords.map((c) => ({ at: at(c.t), name: c.name }));
  const bar = beatsPerBar * QUARTER;
  const end = Math.max(1, ...notesOn.map((n) => n.to), ...chords.map((c) => at(c.t + c.d)));
  const barCount = Math.ceil(end / bar);
  const cuts = new Set([0]);
  for (const n of notesOn) cuts.add(n.from).add(n.to);
  for (const m of marks) cuts.add(m.at);
  for (let b = 0; b <= barCount; b++) cuts.add(b * bar);
  const edges = [...cuts].filter((x) => x <= barCount * bar).sort((a, b) => a - b);

  const measures = Array.from({ length: barCount }, () => ({ beats: [] }));
  for (let i = 0; i < edges.length - 1; i++) {
    const from = edges[i], to = edges[i + 1];
    const playing = notesOn.filter((n) => n.from <= from && n.to > from);
    const text = marks.find((m) => m.at === from)?.name;
    let first = true;
    for (const { value, dotted, length } of lengths(to - from)) {
      measures[Math.floor(from / bar)].beats.push({
        value, dotted,
        rest: playing.length === 0,
        text: first ? text : undefined,
        notes: playing.map((n) => ({
          s: n.s, f: n.f, tie: !first || n.from < from,
          finger: !first || n.from < from ? null : n.finger,
        })),
      });
      first = false;
    }
  }
  return measures;
}

/** A length in 64ths as note values: the longest that fit, dotted ones too. */
function lengths(units) {
  const out = [];
  const values = [1, 2, 4, 8, 16, 32, 64].flatMap((value) => {
    const plain = (4 * QUARTER) / value;
    return [{ value, dotted: true, length: plain * 1.5 }, { value, dotted: false, length: plain }];
  }).filter((v) => Number.isInteger(v.length));
  while (units > 0) {
    const v = values.find((x) => x.length <= units);
    out.push(v);
    units -= v.length;
  }
  return out;
}

/**
 * Text as plain ASCII, which every program reads the same way (an 8-bit
 * charset in the file is read differently from program to program):
 * umlauts as ae, oe, ue, accents dropped, Arabic letters spelt in Latin ones.
 */
const ARABIC = {
  'ا': 'a', 'أ': 'a', 'إ': 'i', 'آ': 'a', 'ب': 'b', 'ت': 't', 'ث': 'th', 'ج': 'j', 'ح': 'h', 'خ': 'kh',
  'د': 'd', 'ذ': 'dh', 'ر': 'r', 'ز': 'z', 'س': 's', 'ش': 'sh', 'ص': 's', 'ض': 'd', 'ط': 't', 'ظ': 'z',
  'ع': "'", 'غ': 'gh', 'ف': 'f', 'ق': 'q', 'ك': 'k', 'ل': 'l', 'م': 'm', 'ن': 'n', 'ه': 'h', 'و': 'w',
  'ي': 'y', 'ى': 'a', 'ة': 'a', 'ء': "'", 'ئ': "'", 'ؤ': "'", '،': ',', '؟': '?', '؛': ';',
};
const SIGNS = {
  'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'Ä': 'Ae', 'Ö': 'Oe', 'Ü': 'Ue', 'ß': 'ss', '‘': "'", '’': "'",
  '‚': "'", '“': '"', '”': '"', '„': '"', '–': '-', '—': '-', '…': '...', '½': '1/2', '♯': '#', '♭': 'b',
};
export function ascii(text) {
  return [...(text ?? '')
    .replace(/[\u064b-\u0652\u0640]/g, '') // vowel marks, tatweel
    .replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x660))
    .replace(/[\u0600-\u06ff]+/g, (word) => {
      const spelt = [...word].map((c) => ARABIC[c] ?? '').join('');
      return spelt.charAt(0).toUpperCase() + spelt.slice(1);
    })]
    .map((c) => SIGNS[c] ?? c.normalize('NFD').replace(/[\u0300-\u036f]/g, ''))
    .join('')
    .replace(/[^\x20-\x7e]/g, '?');
}
const encode = (text) => [...ascii(text)].map((c) => c.charCodeAt(0));

class Writer {
  bytes = [];
  u8(v) { this.bytes.push(v & 0xff); }
  i8(v) { this.u8(v); }
  bool(v) { this.u8(v ? 1 : 0); }
  i16(v) { this.u8(v); this.u8(v >> 8); }
  i32(v) { for (let i = 0; i < 4; i++) this.u8(v >> (8 * i)); }
  zeros(n) { for (let i = 0; i < n; i++) this.u8(0); }
  /** Length byte, then the text padded to [size]. */
  byteSizeString(text, size) {
    const b = encode(text).slice(0, size);
    this.u8(b.length);
    this.bytes.push(...b);
    this.zeros(size - b.length);
  }
  /** Length + 1 as int, length byte, the text. */
  intByteSizeString(text) {
    const b = encode(text).slice(0, 255);
    this.i32(b.length + 1);
    this.u8(b.length);
    this.bytes.push(...b);
  }
}

/**
 * The song as a .gp5 file: one guitar track in standard tuning with the
 * tab, the fingers (1 index … 4 little finger), the chords as text over
 * the beats and the key the notes are in. meta: {title, artist, bpm, ticksPerBeat, beatsPerBar}.
 */
export function gp5(meta, notes, chords = []) {
  const ticksPerBeat = meta.ticksPerBeat ?? 4, beatsPerBar = meta.beatsPerBar ?? 4;
  const measures = tabMeasures({ notes, chords, ticksPerBeat, beatsPerBar });
  const key = keySignature(notes);
  const w = new Writer();
  w.byteSizeString('FICHIER GUITAR PRO v5.10', 30);

  // Song information: title, subtitle, artist, album, words, music,
  // copyright, tab, instructions; no notice lines.
  for (const text of [meta.title, '', meta.artist, '', '', '', '', 'Yalla Studio', '']) w.intByteSizeString(text ?? '');
  w.i32(0);
  // No lyrics: track choice, five empty lines from bar 1.
  w.i32(0);
  for (let i = 0; i < 5; i++) { w.i32(1); w.i32(0); }
  // Master effect: volume, unknown, a flat 10-band equalizer and gain.
  w.i32(100); w.i32(0); w.zeros(11);
  // Page setup: A4, margins, 100 %, every header and footer.
  for (const v of [210, 297, 10, 10, 15, 10, 100]) w.i32(v);
  w.u8(0xff); w.u8(0x01);
  for (const text of ['%title%', '%subtitle%', '%artist%', '%album%', 'Words by %words%', 'Music by %music%',
    'Words & Music by %WORDSMUSIC%', 'Copyright %copyright%',
    'All Rights Reserved - International Copyright Secured', 'Page %N%/%P%']) w.intByteSizeString(text);
  w.intByteSizeString('Moderate');
  w.i32(Math.round(meta.bpm ?? 90));
  w.bool(false); // tempo shown
  w.i8(key.fifths); w.i32(0); // key, octave

  // 64 MIDI channels: the guitar on 1 (effects on 2), the rest as default.
  for (let channel = 0; channel < 64; channel++) {
    w.i32(channel % 16 === 9 ? -1 : 25); // acoustic guitar; drums
    for (const v of [104, 64, 0, 0, 0, 0]) w.i8(Math.min(Math.max((v >> 3) - 1, -128), 127) + 1);
    w.zeros(2);
  }
  for (let i = 0; i < 19; i++) w.i16(-1); // no coda, segno …
  w.i32(0); // master reverb
  w.i32(measures.length);
  w.i32(1); // tracks

  measures.forEach((_, i) => {
    if (i > 0) w.zeros(1);
    if (i === 0) {
      w.u8(0x43); // time and key signature
      w.i8(beatsPerBar); w.i8(4);
      w.i8(key.fifths); w.i8(key.minor ? 1 : 0);
      for (const beam of [2, 2, 2, 2]) w.u8(beam);
    } else {
      w.u8(0x00);
    }
    w.zeros(1);
    w.u8(0); // no triplet feel
  });

  // The track.
  w.zeros(1);
  w.u8(0x08); // visible
  w.byteSizeString('Gitarre', 40);
  w.i32(6);
  for (let i = 0; i < 7; i++) w.i32(TUNING[i] ?? 0);
  w.i32(1); // port
  w.i32(1); w.i32(2); // channel, effect channel
  w.i32(24); // frets
  w.i32(0); // capo
  w.u8(255); w.u8(0); w.u8(0); w.zeros(1); // colour
  w.i16(0x0043); // tab, notation, chord diagram list
  w.u8(0); w.u8(0); // accentuation, bank
  // RSE: humanize, unknowns, instrument, equalizer, effect.
  w.u8(0); w.i32(0); w.i32(0); w.i32(100); w.zeros(12);
  w.i32(-1); w.i32(-1); w.i32(-1); w.i32(-1);
  w.zeros(4);
  w.intByteSizeString(''); w.intByteSizeString('');
  w.zeros(1);

  for (const measure of measures) {
    w.i32(measure.beats.length);
    for (const beat of measure.beats) writeBeat(w, beat);
    // The second voice: one empty beat, as Guitar Pro writes it.
    w.i32(1);
    w.u8(0x40); w.u8(0); w.i8(0); w.u8(0); w.i16(0);
    w.u8(0); // no line break
  }
  return Uint8Array.from(w.bytes);
}

/**
 * The key signature for the notes, so that notation spells them as the
 * key does (B flat in D minor, not A sharp): of all signatures the one
 * whose scale holds most of the notes, near the key the notes sound in.
 * Returns sharps (+) or flats (−) and whether the key is minor.
 */
export function keySignature(notes) {
  if (!notes.length) return { fifths: 0, minor: false };
  const { tonic, minor } = findKey(notes);
  const fifthsOf = (major) => { const f = (major * 7) % 12; return f > 6 ? f - 12 : f; };
  const heard = fifthsOf((tonic + (minor ? 3 : 0)) % 12);
  let best = null;
  for (let fifths = -6; fifths <= 6; fifths++) {
    const major = (((fifths * 7) % 12) + 12) % 12;
    const scale = [0, 2, 4, 5, 7, 9, 11].map((i) => (major + i) % 12);
    const off = notes.reduce((sum, n) => sum + (scale.includes(midiOf(n.s, n.f) % 12) ? 0 : n.d), 0);
    // Fewest notes off the scale, then nearest the key heard, then plainest.
    const score = [off, Math.abs(fifths - heard), Math.abs(fifths)];
    if (!best || score.reduce((r, x, i) => r || x - best.score[i], 0) < 0) best = { fifths, score };
  }
  return { fifths: best.fifths, minor };
}

function writeBeat(w, beat) {
  let flags = 0;
  if (beat.dotted) flags |= 0x01;
  if (beat.text) flags |= 0x04;
  if (beat.rest) flags |= 0x40;
  w.u8(flags);
  if (beat.rest) w.u8(2);
  w.i8(Math.log2(beat.value) - 2);
  if (beat.text) w.intByteSizeString(beat.text);
  const notes = beat.rest ? [] : [...beat.notes].sort((a, b) => a.s - b.s);
  w.u8(notes.reduce((bits, n) => bits | (1 << (7 - n.s)), 0));
  for (const n of notes) {
    const finger = !n.tie && n.finger >= 1 && n.finger <= 4;
    w.u8(0x20 | (finger ? 0x88 : 0));
    w.u8(n.tie ? 2 : 1);
    w.i8(n.tie ? 0 : n.f);
    if (finger) { w.i8(n.finger); w.i8(-1); }
    w.u8(0);
    if (finger) { w.i8(0); w.i8(0); }
  }
  w.i16(0);
}
