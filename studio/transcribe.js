// Yalla Studio: from detected notes to a playable guitar chart.
// Pure functions, no browser APIs, so they run under `node --test` too.

/** Open strings, 1 = high E … 6 = low E, as MIDI notes. */
export const OPEN_STRINGS = [64, 59, 55, 50, 45, 40];
export const MAX_FRET = 15;
const NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

export const midiOf = (s, f) => OPEN_STRINGS[s - 1] + f;
export const noteName = (midi) => NAMES[midi % 12] + (Math.floor(midi / 12) - 1);
export const hz = (midi) => 440 * 2 ** ((midi - 69) / 12);

/**
 * Keeps the melody from detected notes ({start, duration, midi, amplitude}):
 * drops what a guitar cannot play, overtones and ringing tails, and of notes
 * starting together keeps the highest, which carries the tune.
 */
export function melodyOf(notes, { together = 0.06 } = {}) {
  const lowest = OPEN_STRINGS[5], highest = OPEN_STRINGS[0] + MAX_FRET + 5;
  const sorted = notes
    .filter((n) => n.midi >= lowest && n.midi <= highest && n.duration > 0.04)
    .sort((a, b) => a.start - b.start);
  const clusters = [];
  for (const n of sorted) {
    const last = clusters[clusters.length - 1];
    if (last && n.start - last[0].start <= together) last.push(n);
    else clusters.push([n]);
  }
  const melody = [];
  for (const cluster of clusters) {
    // Overtones: an octave, octave and fifth or two octaves over a note
    // that starts with them.
    const real = cluster.filter(
      (n) => !cluster.some((o) => o !== n && [12, 19, 24, 28, 31].includes(n.midi - o.midi)),
    );
    const previous = melody[melody.length - 1];
    // A string still ringing from the note before, heard again next to the
    // new note: the new one is the melody.
    const fresh = real.filter((n) => !(previous && n.midi === previous.midi &&
      n.start < previous.start + previous.duration + 0.1));
    const choice = fresh.length ? fresh : real.length ? real : cluster;
    const top = choice.reduce((a, b) => (b.midi > a.midi ? b : a));
    // A string still ringing, heard as a new note of the same pitch.
    const tail = previous && previous.midi === top.midi &&
      top.start < previous.start + previous.duration &&
      top.amplitude < previous.amplitude * 0.9;
    if (!tail) melody.push(top);
  }
  return melody;
}

/**
 * Finds the beat: the longest time step that the gaps between notes are
 * whole multiples of, taken as a quarter or eighth so the tempo lands
 * between 70 and 140 BPM. Returns {bpm, offset}: the time of the first beat.
 */
export function detectTempo(melody, { ticksPerBeat = 4 } = {}) {
  const starts = melody.map((n) => n.start);
  if (starts.length < 3) return { bpm: 90, offset: starts[0] ?? 0 };
  const gaps = [];
  for (let i = 1; i < starts.length; i++) {
    const g = starts[i] - starts[i - 1];
    if (g > 0.08 && g < 3) gaps.push(g);
  }
  let unit = 0.25;
  for (let u = 1.2; u >= 0.08; u -= 0.002) {
    const fits = gaps.filter((g) => {
      const k = Math.round(g / u);
      return k >= 1 && Math.abs(g - k * u) <= 0.12 * u;
    }).length;
    if (fits >= 0.9 * gaps.length) {
      unit = u;
      break;
    }
  }
  // Refine the unit by least squares over the gaps it explains.
  let num = 0, den = 0;
  for (const g of gaps) {
    const k = Math.round(g / unit);
    if (k >= 1 && Math.abs(g - k * unit) <= 0.12 * unit) {
      num += g * k;
      den += k * k;
    }
  }
  if (den > 0) unit = num / den;
  let beat = unit;
  while (60 / beat > 140) beat *= 2;
  while (60 / beat < 70) beat /= 2;
  // Fit grid and start note by note (least squares over the notes so far),
  // each placed with the grid found before it: a small error in the first
  // guess cannot add up over the song.
  let tick = beat / ticksPerBeat, offset = starts[0];
  const ks = [0];
  for (let i = 1; i < starts.length; i++) {
    ks.push(Math.round((starts[i] - offset) / tick));
    const n = i + 1, xs = ks, ys = starts.slice(0, n);
    const mk = xs.reduce((a, b) => a + b) / n, mt = ys.reduce((a, b) => a + b) / n;
    let sxy = 0, sxx = 0;
    xs.forEach((k, j) => { sxy += (k - mk) * (ys[j] - mt); sxx += (k - mk) ** 2; });
    if (sxx > 0 && n >= 4) {
      tick = sxy / sxx;
      offset = mt - tick * mk;
    }
  }
  // The first note starts the song: the grid's origin is moved onto it.
  const first = Math.round((starts[0] - offset) / tick);
  offset += first * tick;
  return { bpm: Math.round((60 / (tick * ticksPerBeat)) * 10) / 10, offset };
}

/**
 * Puts the melody on the tick grid: {tick, length} per note, lengths
 * reaching the next note unless it starts much later.
 */
export function quantize(melody, { bpm, offset, ticksPerBeat = 4 }) {
  const tick = 60 / bpm / ticksPerBeat;
  const out = [];
  for (const n of melody) {
    const t = Math.max(0, Math.round((n.start - offset) / tick));
    if (out.length && out[out.length - 1].tick === t) continue; // one note per step
    out.push({ tick: t, midi: n.midi, length: Math.max(1, Math.round(n.duration / tick)), amplitude: n.amplitude });
  }
  for (let i = 0; i < out.length - 1; i++) {
    const room = out[i + 1].tick - out[i].tick;
    // Guitar notes ring on: close small gaps, keep real rests.
    out[i].length = room - out[i].length <= 2 * ticksPerBeat ? room : Math.min(out[i].length, room);
  }
  return out;
}

/** Every string and fret that plays [midi]. */
export function positions(midi) {
  const out = [];
  for (let s = 1; s <= 6; s++) {
    const f = midi - OPEN_STRINGS[s - 1];
    if (f >= 0 && f <= MAX_FRET) out.push({ s, f });
  }
  return out;
}

/**
 * Chooses string and fret for every pitch so the hand moves least:
 * a shortest path over all positions (Viterbi). Open strings are free
 * for the hand; high frets and big string skips cost a little.
 */
export function assignTab(midis) {
  const options = midis.map((m) => {
    const p = positions(m);
    // Out of range: transpose into it by octaves.
    return p.length ? p : positions(m < OPEN_STRINGS[5] ? m + 12 * Math.ceil((OPEN_STRINGS[5] - m) / 12) : m - 12 * Math.ceil((m - OPEN_STRINGS[0] - MAX_FRET) / 12));
  });
  const own = (o) => 0.04 * o.f + (o.f > 12 ? 0.5 : 0);
  const move = (a, b) => {
    if (a.f === 0 || b.f === 0) return 0.3 * Math.abs(a.s - b.s) / 2;
    const reach = Math.abs(a.f - b.f);
    return (reach <= 3 ? reach * 0.2 : 1 + reach * 0.4) + 0.15 * Math.abs(a.s - b.s);
  };
  let cost = options[0].map(own);
  const back = [];
  for (let i = 1; i < options.length; i++) {
    const next = [], from = [];
    for (const b of options[i]) {
      let best = Infinity, arg = 0;
      options[i - 1].forEach((a, j) => {
        const c = cost[j] + move(a, b);
        if (c < best) { best = c; arg = j; }
      });
      next.push(best + own(b));
      from.push(arg);
    }
    back.push(from);
    cost = next;
  }
  let j = cost.indexOf(Math.min(...cost));
  const out = new Array(options.length);
  for (let i = options.length - 1; i >= 0; i--) {
    out[i] = options[i][j];
    if (i > 0) j = back[i - 1][j];
  }
  return out;
}

/**
 * One finger per fret, as in the app: the hand sits with the index at fret
 * p and fingers 1–4 over frets p … p+3, shifting as little as possible.
 */
export function assignFingers(frets) {
  const maxPosition = 20;
  const fits = (p, f) => f === 0 || (f >= p && f <= p + 3);
  let cost = [];
  for (let p = 0; p <= maxPosition; p++) cost.push(p === 0 || !fits(p, frets[0] ?? 0) ? Infinity : p * 0.001);
  const back = [];
  for (let i = 1; i < frets.length; i++) {
    const next = new Array(maxPosition + 1).fill(Infinity), from = new Array(maxPosition + 1).fill(0);
    for (let p = 1; p <= maxPosition; p++) {
      if (!fits(p, frets[i])) continue;
      for (let q = 1; q <= maxPosition; q++) {
        if (cost[q] === Infinity) continue;
        const c = cost[q] + (p === q ? 0 : 1 + 0.05 * Math.abs(p - q)) + p * 0.001;
        if (c < next[p]) { next[p] = c; from[p] = q; }
      }
    }
    back.push(from);
    cost = next;
  }
  if (!frets.length) return [];
  let p = 1;
  for (let q = 1; q <= maxPosition; q++) if (cost[q] < cost[p]) p = q;
  const positionsOut = new Array(frets.length);
  for (let i = frets.length - 1; i >= 0; i--) {
    positionsOut[i] = p;
    if (i > 0) p = back[i - 1][p];
  }
  return frets.map((f, i) => (f === 0 ? 0 : f - positionsOut[i] + 1));
}

/** The whole way from detected notes to chart notes {t, s, f, d, finger}. */
export function chartNotes(detected, { bpm, offset, ticksPerBeat = 4, melodyOnly = true }) {
  const melody = melodyOnly ? melodyOf(detected) : [...detected].sort((a, b) => a.start - b.start);
  const grid = quantize(melody, { bpm, offset, ticksPerBeat });
  const tab = assignTab(grid.map((n) => n.midi));
  const fingers = assignFingers(tab.map((p) => p.f));
  return grid.map((n, i) => ({ t: n.tick, s: tab[i].s, f: tab[i].f, d: n.length, finger: fingers[i] }));
}

/** A chart in the app's `yalla-song/1` format, one note per line. */
export function toJson(meta, notes) {
  const head = {
    format: 'yalla-song/1',
    id: meta.id,
    title: meta.title,
    artist: meta.artist ?? '',
    bpm: meta.bpm,
    ticksPerBeat: meta.ticksPerBeat ?? 4,
    beatsPerBar: meta.beatsPerBar ?? 4,
  };
  const lines = [...notes]
    .sort((a, b) => a.t - b.t)
    .map((n) => '    ' + JSON.stringify({ t: n.t, s: n.s, f: n.f, d: n.d, ...(n.finger == null ? {} : { finger: n.finger }) }).replaceAll(',', ', ').replaceAll(':', ': '));
  const top = JSON.stringify(head, null, 2);
  return top.slice(0, -2) + ',\n  "notes": [\n' + lines.join(',\n') + '\n  ]\n}\n';
}

/** Reads a `yalla-song/1` file back for editing; throws on a broken one. */
export function fromJson(text) {
  const data = JSON.parse(text);
  if (data.format !== 'yalla-song/1') throw new Error('Keine yalla-song/1 Datei');
  if (!Array.isArray(data.notes) || !data.notes.length) throw new Error('Die Datei enthält keine Noten');
  for (const n of data.notes) {
    if (!(n.s >= 1 && n.s <= 6 && n.f >= 0 && n.f <= 24 && n.d >= 1 && n.t >= 0)) {
      throw new Error('Ungültige Note: ' + JSON.stringify(n));
    }
  }
  return data;
}

/** A file name from a title: lower case letters, digits and dashes. */
export function slug(title) {
  const s = title.normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return s || 'song';
}
