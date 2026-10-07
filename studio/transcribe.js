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
  const playable = notes.filter((n) => n.midi >= lowest && n.midi <= highest && n.duration > 0.04);
  // Room noise, hum and sympathetic strings come out much quieter than
  // the notes played.
  const typical = [...playable.map((n) => n.amplitude)].sort((a, b) => a - b)[Math.floor(playable.length / 2)] ?? 0;
  const sorted = mergeGlitches(playable.filter((n) => n.amplitude >= 0.68 * typical))
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
 * The melody of a whole song, with accompaniment and bass around it: the
 * one line through the detected notes that is loud, sits high, moves in
 * small steps and does not start under a melody note still ringing — a
 * best path (dynamic programming) over all notes, one note at a time.
 */
export function melodyTrack(notes, { gap = 0.08, window = 4 } = {}) {
  const lowest = OPEN_STRINGS[5], highest = OPEN_STRINGS[0] + MAX_FRET + 5;
  const playable = notes.filter((n) => n.midi >= lowest && n.midi <= highest && n.duration > 0.04);
  const median = (xs) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)] ?? 0;
  const loud = median(playable.map((n) => n.amplitude));
  const all = mergeGlitches(playable.filter((n) => n.amplitude >= 0.5 * loud))
    .sort((a, b) => a.start - b.start || b.midi - a.midi);
  if (!all.length) return [];
  // The melody's register: from a fourth below where the upper part of
  // the notes lies; notes far below it are likely bass and chords.
  const pitches = all.map((n) => n.midi).sort((a, b) => a - b);
  const floor = pitches[Math.floor(pitches.length * 0.75)] - 5;
  // Notes starting together with each note.
  const together = all.map((n, i) => {
    const out = [];
    for (let j = i - 1; j >= 0 && all[j].start > n.start - 0.06; j--) out.push(j);
    for (let j = i + 1; j < all.length && all[j].start < n.start + 0.06; j++) out.push(j);
    return out;
  });
  const overtone = (i, louder) => together[i].some((j) =>
    [12, 19, 24, 28].includes(all[i].midi - all[j].midi) && all[j].amplitude > all[i].amplitude * louder);
  const salience = all.map((n, i) => {
    const height = (n.midi - floor) / 12;
    const place = height < 0 ? Math.max(-1.2, height) * 0.9 : Math.min(0.5, height) * 0.2;
    // The tune is mostly the top voice; overtones above it do not count.
    const top = !together[i].some((j) => all[j].midi > n.midi && !overtone(j, 1));
    return n.amplitude / loud - 0.85 + place + 0.1 * Math.min(1, n.duration / 0.4) +
      (top ? 0.15 : 0) - (overtone(i, 1.5) ? 0.4 : 0);
  });
  const step = (a, b) => {
    const jump = Math.abs(b.midi - a.midi);
    let cost = 0.01 * jump + (jump > 9 ? 0.1 : 0) + (jump > 12 ? 0.3 : 0);
    // Struck while the melody note before still rings, and well below it:
    // accompaniment.
    if (b.start < a.start + a.duration - 0.05 && b.midi < a.midi - 4) cost += 0.35;
    // The same pitch again while it still rings: the string ringing on.
    if (b.midi === a.midi && b.start < a.start + a.duration && b.amplitude < a.amplitude * 0.9) cost += 0.5;
    return cost;
  };
  const best = new Array(all.length), from = new Array(all.length);
  let doneBest = 0, doneArg = -1, done = 0; // best path among notes outside the window
  for (let i = 0; i < all.length; i++) {
    const b = all[i];
    while (done < i && all[done].start < b.start - window) {
      if (best[done] > doneBest) { doneBest = best[done]; doneArg = done; }
      done++;
    }
    let value = doneBest, arg = doneArg;
    for (let j = done; j < i; j++) {
      if (all[j].start > b.start - gap) break;
      const v = best[j] - step(all[j], b);
      if (v > value) { value = v; arg = j; }
    }
    best[i] = salience[i] + value;
    from[i] = arg;
  }
  let i = best.indexOf(Math.max(...best));
  const melody = [];
  for (; i >= 0; i = from[i]) melody.push(all[i]);
  melody.reverse();
  // Accompaniment the path took in the melody's rests lies far below the
  // tune around it.
  return melody.filter((n) => {
    const around = melody.filter((o) => o !== n && Math.abs(o.start - n.start) < window).map((o) => o.midi);
    return around.length < 3 || n.midi > median(around) - 10;
  });
}

/**
 * A pluck often starts a little off pitch and settles a moment later; the
 * detector then hears a short note and the real one right after. Those
 * become one note, starting with the pluck.
 */
function mergeGlitches(notes) {
  const sorted = notes.map((n) => ({ ...n })).sort((a, b) => a.start - b.start);
  const out = [];
  for (let i = 0; i < sorted.length; i++) {
    const n = sorted[i];
    const next = sorted.slice(i + 1).find((m) => m.start > n.start + 0.03 && m.start - n.start < 0.25 &&
      Math.abs(m.midi - n.midi) <= 2 && m.duration > n.duration);
    if (n.duration < 0.2 && next) {
      next.duration += next.start - n.start;
      next.start = n.start;
      next.amplitude = Math.max(next.amplitude, n.amplitude);
      continue;
    }
    out.push(n);
  }
  return out;
}

/**
 * Finds the tempo: for every tempo from 50 to 200 BPM, how well all note
 * starts sit on its grid of eighth notes (weighted by loudness, as a
 * circular mean, so stray notes and a player's small wobbles count little).
 * The slowest tempo that fits about as well as the best is taken, since
 * every faster multiple fits too; then it is folded into 70–140 BPM.
 * Returns {bpm, offset}: the time of the first note, on the grid.
 */
export function detectTempo(melody, { ticksPerBeat = 4 } = {}) {
  const starts = melody.map((n) => n.start);
  if (starts.length < 3) return { bpm: 90, offset: starts[0] ?? 0 };
  const weights = melody.map((n) => n.amplitude ?? 1);
  const total = weights.reduce((a, b) => a + b);
  const fit = (bpm) => {
    const grid = 60 / bpm / 2;
    let re = 0, im = 0;
    starts.forEach((t, i) => {
      const angle = (2 * Math.PI * t) / grid;
      re += weights[i] * Math.cos(angle);
      im += weights[i] * Math.sin(angle);
    });
    return Math.hypot(re, im) / total;
  };
  const scores = [];
  for (let bpm = 50; bpm <= 200; bpm += 0.25) scores.push({ bpm, score: fit(bpm) });
  const best = Math.max(...scores.map((s) => s.score));
  // Local peaks close to the best; the slowest of them.
  const peaks = scores.filter((s, i) =>
    s.score >= 0.85 * best &&
    (i === 0 || s.score >= scores[i - 1].score) &&
    (i === scores.length - 1 || s.score >= scores[i + 1].score));
  let bpm = peaks[0].bpm;
  while (bpm < 70) bpm *= 2;
  while (bpm > 140) bpm /= 2;
  const beat = 60 / bpm;

  // Fit grid and start note by note (least squares over the notes so far),
  // each placed with the grid found before it: a small error in the first
  // guess cannot add up over the song. Notes far off the grid (a late
  // detection, a grace note) are left out of the fit.
  let tick = beat / ticksPerBeat, offset = starts[0];
  const xs = [0], ys = [starts[0]];
  for (let i = 1; i < starts.length; i++) {
    const k = Math.round((starts[i] - offset) / tick);
    if (Math.abs(starts[i] - offset - k * tick) > 0.3 * tick && xs.length >= 4) continue;
    xs.push(k);
    ys.push(starts[i]);
    const n = xs.length;
    const mk = xs.reduce((a, b) => a + b) / n, mt = ys.reduce((a, b) => a + b) / n;
    let sxy = 0, sxx = 0;
    xs.forEach((x, j) => { sxy += (x - mk) * (ys[j] - mt); sxx += (x - mk) ** 2; });
    if (sxx > 0 && n >= 4) {
      tick = sxy / sxx;
      offset = mt - tick * mk;
    }
  }
  // Then all notes again on the grid found, a few times over.
  for (let round = 0; round < 3; round++) {
    const fx = [], fy = [];
    starts.forEach((t) => {
      const k = Math.round((t - offset) / tick);
      if (Math.abs(t - offset - k * tick) <= 0.25 * tick) { fx.push(k); fy.push(t); }
    });
    const n = fx.length;
    if (n < 4) break;
    const mk = fx.reduce((a, b) => a + b) / n, mt = fy.reduce((a, b) => a + b) / n;
    let sxy = 0, sxx = 0;
    fx.forEach((x, j) => { sxy += (x - mk) * (fy[j] - mt); sxx += (x - mk) ** 2; });
    if (sxx > 0) { tick = sxy / sxx; offset = mt - tick * mk; }
  }
  // With many notes off the grid (a busy recording) the fit can drift; the
  // tempo that best fits all notes at once then wins.
  let fine = bpm, fineScore = -1;
  for (let b = bpm - 1.5; b <= bpm + 1.5; b += 0.05) {
    const score = fit(b);
    if (score > fineScore) { fineScore = score; fine = b; }
  }
  const fitted = 60 / (tick * ticksPerBeat);
  if (fit(fitted) < fineScore - 0.05) {
    tick = 60 / fine / ticksPerBeat;
    // The grid's phase: the circular mean of the starts.
    let re = 0, im = 0;
    starts.forEach((t, i) => {
      re += weights[i] * Math.cos((2 * Math.PI * t) / tick);
      im += weights[i] * Math.sin((2 * Math.PI * t) / tick);
    });
    offset = (Math.atan2(im, re) / (2 * Math.PI)) * tick;
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
    // Attacks are heard a little late rather than early: round towards the
    // earlier step a bit more readily.
    const t = Math.max(0, Math.round((n.start - offset) / tick - 0.12));
    const note = { tick: t, midi: n.midi, length: Math.max(1, Math.round(n.duration / tick)), amplitude: n.amplitude, duration: n.duration };
    const last = out[out.length - 1];
    // One note per step: a grace note just before the note it leads to
    // gives way to it.
    if (last && last.tick === t) {
      if (n.duration > last.duration * 1.5) out[out.length - 1] = note;
      continue;
    }
    out.push(note);
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

/**
 * The melody by recognition mode: 'single' for one voice alone (a guitar
 * playing the tune), 'song' for a tune within accompaniment, 'all' keeps
 * every note.
 */
export function pickMelody(detected, mode = 'single') {
  if (mode === 'song') return melodyTrack(detected);
  if (mode === 'all') return [...detected].sort((a, b) => a.start - b.start);
  return melodyOf(detected);
}

/**
 * Makes a gridded melody ({tick, midi, length}) easier to play.
 * Level 1 drops ornaments: a lone note of one step that leads straight
 * into a longer note close by (a grace note), leaving runs alone. Level 2 also drops every note followed within less than an eighth, a note
 * jumping away and straight back (more than a fifth both ways), and plays
 * repeated notes as one long note. The note before takes up the time.
 */
export function simplify(grid, level = 0, { ticksPerBeat = 4 } = {}) {
  let out = grid.map((n) => ({ ...n }));
  if (level <= 0 || out.length < 2) return out;
  const step = Math.max(1, Math.round(ticksPerBeat / 4));
  const drop = (keep) => {
    const kept = [];
    out.forEach((n, i) => {
      if (keep(n, i, kept[kept.length - 1])) kept.push(n);
      else if (kept.length) {
        const before = kept[kept.length - 1];
        // The note before rings on through the dropped one.
        if (before.tick + before.length >= n.tick) before.length = n.tick + n.length - before.tick;
      }
    });
    out = kept;
  };
  drop((n, i, before) => {
    const next = out[i + 1];
    const ornament = n.length <= step && next && next.tick - n.tick <= step && next.length >= 2 * n.length &&
      Math.abs(next.midi - n.midi) <= 3 && !(before && before.length <= step);
    return !ornament;
  });
  if (level >= 2) {
    const eighth = Math.max(1, Math.round(ticksPerBeat / 2));
    drop((n, i) => i === 0 || i === out.length - 1 || out[i + 1].tick - n.tick >= eighth);
    drop((n, i, before) => {
      const next = out[i + 1];
      return !(before && next && Math.abs(n.midi - before.midi) > 7 && Math.abs(n.midi - next.midi) > 7 &&
        Math.abs(next.midi - before.midi) <= 7);
    });
    drop((n, i, before) => !(before && before.midi === n.midi && before.tick + before.length >= n.tick));
  }
  return out;
}

const LOW = OPEN_STRINGS[5], HIGH = OPEN_STRINGS[0] + MAX_FRET;

/**
 * Shifts by [semitones], then moves any note the guitar cannot play by
 * octaves into its range.
 */
export function transpose(grid, semitones = 0) {
  return grid.map((n) => {
    let midi = n.midi + semitones;
    while (midi < LOW) midi += 12;
    while (midi > HIGH) midi -= 12;
    return { ...n, midi };
  });
}

/**
 * The whole way from detected notes to chart notes {t, s, f, d, finger}:
 * mode as in pickMelody, simplify level 0–2, transpose in semitones.
 */
export function chartNotes(detected, { bpm, offset, ticksPerBeat = 4, mode = 'single', simplify: level = 0, transpose: shift = 0 }) {
  const melody = pickMelody(detected, mode);
  const grid = transpose(simplify(quantize(melody, { bpm, offset, ticksPerBeat }), level, { ticksPerBeat }), shift);
  if (!grid.length) return [];
  const tab = assignTab(grid.map((n) => n.midi));
  const fingers = assignFingers(tab.map((p) => p.f));
  return grid.map((n, i) => ({ t: n.tick, s: tab[i].s, f: tab[i].f, d: n.length, finger: fingers[i] }));
}

// ---------------------------------------------------------------- chords

/** Chord types by suffix; the same table is in the app's chord_symbol.dart. */
export const CHORD_QUALITIES = {
  '': [0, 4, 7], m: [0, 3, 7], 7: [0, 4, 7, 10], maj7: [0, 4, 7, 11], m7: [0, 3, 7, 10],
  6: [0, 4, 7, 9], m6: [0, 3, 7, 9], dim: [0, 3, 6], aug: [0, 4, 8], sus2: [0, 2, 7],
  sus4: [0, 5, 7], add9: [0, 4, 7, 14], 9: [0, 4, 7, 10, 14], 5: [0, 7],
};
export const ROOT_NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const LETTERS = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const pitchOf = (letter, accidental) => (LETTERS[letter] + (accidental === '#' ? 1 : accidental === 'b' ? -1 : 0) + 12) % 12;

/** Reads `Dm`, `A7`, `C/E` … into {root, quality, intervals, bass}, or null. */
export function parseChord(name) {
  const m = /^([A-G])([#b]?)([a-z0-9]*)(?:\/([A-G])([#b]?))?$/.exec((name ?? '').trim());
  if (!m || !Object.hasOwn(CHORD_QUALITIES, m[3])) return null;
  const root = pitchOf(m[1], m[2]);
  const bass = m[4] ? pitchOf(m[4], m[5]) : null;
  return { root, quality: m[3], intervals: CHORD_QUALITIES[m[3]], bass: bass === root ? null : bass };
}

/** The name of a chord from its parts. */
export const chordName = (root, quality, bass = null) =>
  ROOT_NAMES[root] + quality + (bass == null || bass === root ? '' : '/' + ROOT_NAMES[bass]);

/** A chord name moved by [semitones]: `Dm` +2 → `Em`, `C/E` −1 → `B/Eb`. */
export function transposeChord(name, semitones) {
  const c = parseChord(name);
  if (!c) return name;
  const move = (pc) => (((pc + semitones) % 12) + 12) % 12;
  return chordName(move(c.root), c.quality, c.bass == null ? null : move(c.bass));
}

/** The pitch classes of a chord. */
export const chordTones = (c) => [...new Set(c.intervals.map((i) => (c.root + i) % 12))];

const KEY_MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const KEY_MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

/**
 * Suggests chords for a melody, as the app does when a song has none: the
 * key by the Krumhansl profiles, then per half bar the triad of the key
 * that holds most of the melody, staying on the chord before when that
 * fits as well. Same chords in a row become one. Returns [{t, d, name}].
 */
export function suggestChords(notes, { ticksPerBeat = 4, beatsPerBar = 4 } = {}) {
  if (!notes.length) return [];
  const pc = (n) => midiOf(n.s, n.f) % 12;
  const weight = new Array(12).fill(0);
  for (const n of notes) weight[pc(n)] += n.d;
  let key = { tonic: 0, minor: false }, bestKey = -Infinity;
  for (let tonic = 0; tonic < 12; tonic++) {
    for (const minor of [false, true]) {
      const profile = minor ? KEY_MINOR : KEY_MAJOR;
      let s = 0;
      for (let p = 0; p < 12; p++) s += weight[p] * profile[(p - tonic + 12) % 12];
      if (s > bestKey) { bestKey = s; key = { tonic, minor }; }
    }
  }
  const scale = key.minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11];
  const candidates = [];
  for (let d = 0; d < 7; d++) {
    if ((scale[(d + 4) % 7] - scale[d] + 12) % 12 !== 7) continue; // no diminished
    candidates.push({ root: (key.tonic + scale[d]) % 12, minor: (scale[(d + 2) % 7] - scale[d] + 12) % 12 === 3 });
  }
  if (key.minor) candidates.push({ root: (key.tonic + 7) % 12, minor: false });
  const tones = (c) => [c.root, (c.root + (c.minor ? 3 : 4)) % 12, (c.root + 7) % 12];
  const half = (ticksPerBeat * beatsPerBar) / 2;
  const end = Math.max(...notes.map((n) => n.t + n.d));
  const chords = [];
  let previous = { root: key.tonic, minor: key.minor };
  for (let from = 0; from < end; from += half) {
    const w = new Array(12).fill(0);
    for (const n of notes) {
      const overlap = Math.min(from + half, n.t + n.d) - Math.max(from, n.t);
      if (overlap > 0) w[pc(n)] += overlap;
    }
    const total = w.reduce((a, b) => a + b);
    if (total > 0) {
      const score = (c) => {
        const t = tones(c);
        let s = 0;
        for (let p = 0; p < 12; p++) s += t.includes(p) ? w[p] : -0.5 * w[p];
        if (c.root === previous.root && c.minor === previous.minor) s += 0.15 * total;
        if (c.root === key.tonic) s += 0.05 * total;
        return s;
      };
      previous = candidates.reduce((a, b) => (score(b) > score(a) ? b : a));
    }
    const name = chordName(previous.root, previous.minor ? 'm' : '');
    const last = chords[chords.length - 1];
    if (last && last.name === name) last.d += half;
    else chords.push({ t: from, d: half, name });
  }
  return chords;
}

/** A chart in the app's `yalla-song/1` format, one note per line. */
export function toJson(meta, notes, chords = []) {
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
  const chordLines = [...chords]
    .sort((a, b) => a.t - b.t)
    .map((c) => '    ' + JSON.stringify({ t: c.t, d: c.d, name: c.name }).replaceAll(',', ', ').replaceAll('":', '": '));
  return top.slice(0, -2) + ',\n  "notes": [\n' + lines.join(',\n') + '\n  ]' +
    (chordLines.length ? ',\n  "chords": [\n' + chordLines.join(',\n') + '\n  ]' : '') + '\n}\n';
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
  for (const c of data.chords ?? []) {
    if (!parseChord(c.name) || !(c.d >= 1 && c.t >= 0)) throw new Error('Ungültiger Akkord: ' + JSON.stringify(c));
  }
  return data;
}

/** A file name from a title: lower case letters, digits and dashes. */
export function slug(title) {
  const s = title.normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return s || 'song';
}
