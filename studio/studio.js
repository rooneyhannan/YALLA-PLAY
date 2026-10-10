// Yalla Studio: open a recording, let Basic Pitch find its notes, turn them
// into a guitar tab, correct it by hand and save it as a yalla-song/1 file.
import {
  CHORD_QUALITIES, ROOT_NAMES, assignFingers, chartNotes, chordName, chordTones, detectTempo, fromJson,
  hz, midiOf, noteName, parseChord, pickMelody, positions, slug, suggestChords, toJson, transposeChord,
} from './transcribe.js';
import { gp5 } from './guitarpro.js';

const $ = (id) => document.getElementById(id);
const FINGER_COLORS = ['#9aa0a6', '#4f8bff', '#3ed8e8', '#a27bff', '#e860c0'];
const STRING_NAMES = ['e', 'B', 'G', 'D', 'A', 'E'];

/** Everything the page edits. */
const state = {
  meta: { id: '', title: '', artist: '', bpm: 90, ticksPerBeat: 4, beatsPerBar: 4 },
  /** {t, s, f, d, finger, fingerAuto} */
  notes: [],
  /** The backing's chords: {t, d, name}. */
  chords: [],
  selectedChord: -1,
  /** What Basic Pitch heard, kept to fit the grid again with a new tempo. */
  detected: null,
  /** How the notes came from it: recognition mode, simplify level, transposition. */
  arrange: { mode: 'single', simplify: 0, transpose: 0 },
  /** The recording, and the time in it where tick 0 lies. */
  audio: null,
  offset: 0,
  selected: -1,
  zoom: 22, // pixels per tick
  scroll: 0, // first visible tick
  playhead: 0, // tick
  playing: null,
  edited: false,
};
const undo = [], redo = [];
let ctx;
const audioContext = () => (ctx ??= new AudioContext());
const tickSeconds = () => 60 / state.meta.bpm / state.meta.ticksPerBeat;

// ---------------------------------------------------------------- files

// Emptied after each choice, so choosing the same file again opens it again.
$('open-audio').addEventListener('change', (e) => {
  const file = e.target.files[0];
  e.target.value = '';
  if (file) openAudio(file);
});
$('open-json').addEventListener('change', (e) => {
  const file = e.target.files[0];
  e.target.value = '';
  if (file) openJson(file);
});
const drop = $('drop');
for (const type of ['dragenter', 'dragover']) {
  document.addEventListener(type, (e) => { e.preventDefault(); drop.classList.add('over'); });
}
document.addEventListener('dragleave', () => drop.classList.remove('over'));
document.addEventListener('drop', (e) => {
  e.preventDefault();
  drop.classList.remove('over');
  const file = e.dataTransfer.files[0];
  if (!file) return;
  if (file.name.endsWith('.json')) openJson(file);
  else openAudio(file);
});

async function openAudio(file) {
  if (state.edited && !confirm('Die aktuellen Änderungen gehen verloren. Weiter?')) return;
  diagnose(true, `${browser()} · ${file.name} (${(file.size / 1e6).toFixed(1)} MB)`);
  showProgress('Lese die Aufnahme …', 0);
  try {
    let decoded;
    try {
      decoded = await audioContext().decodeAudioData(await file.arrayBuffer());
      diagnose(false, `gelesen: ${Math.round(decoded.sampleRate / 1000)} kHz, ${decoded.numberOfChannels} Kanal, ${decoded.duration.toFixed(1)} s`);
    } catch {
      throw new Error('Dieses Audioformat kann dein Browser nicht lesen. Versuche MP3 oder WAV, oder einen anderen Browser (Chrome, Edge, Safari).');
    }
    state.audio = decoded;
    const minutes = `${Math.floor(decoded.duration / 60)}:${String(Math.round(decoded.duration % 60)).padStart(2, '0')}`;
    let shown = '';
    const detected = await transcribe(decoded, (p, engine) => {
      if (engine !== shown) diagnose(false, `Erkennung: ${(shown = engine)}`);
      showProgress(`Erkenne Noten … ${Math.round(p * 100)} % · Aufnahme ${minutes} min · ${engine}`, p);
    });
    diagnose(false, `${detected.length} Töne gehört`);
    state.detected = detected;
    const mode = document.querySelector('input[name="open-mode"]:checked')?.value ?? 'single';
    state.arrange = { mode, simplify: 0, transpose: 0 };
    const melody = pickMelody(detected, mode);
    if (!melody.length) throw new Error('In der Aufnahme wurden keine Gitarrennoten gefunden.');
    const tempo = detectTempo(melody, { ticksPerBeat: 4 });
    const title = file.name.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' ');
    state.meta = { id: slug(title), title, artist: '', bpm: tempo.bpm, ticksPerBeat: 4, beatsPerBar: 4 };
    state.offset = tempo.offset;
    setNotes(chartNotes(detected, { ...tempo, ticksPerBeat: 4, ...state.arrange }).map((n) => ({ ...n, fingerAuto: true })));
    state.chords = [];
    undo.length = redo.length = 0;
    state.edited = false;
    openEditor(`${state.notes.length} Noten erkannt · Tempo ${tempo.bpm} BPM`);
  } catch (error) {
    if (error.cancelled) return hideProgress();
    console.error(error);
    // Stays on screen with the diagnostics, for a screenshot.
    clearInterval(progressClock);
    $('progress-text').textContent = 'Fehler: ' + (error.message ?? error);
    $('progress-text').classList.add('error');
    diagnose(false, 'Fehler: ' + (error.message ?? error));
  } finally {
    cancelRecognition = null;
  }
}

async function openJson(file) {
  if (state.edited && !confirm('Die aktuellen Änderungen gehen verloren. Weiter?')) return;
  try {
    const data = fromJson(await file.text());
    state.meta = {
      id: data.id ?? slug(data.title ?? 'song'), title: data.title ?? '', artist: data.artist ?? '',
      bpm: data.bpm ?? 90, ticksPerBeat: data.ticksPerBeat ?? 4, beatsPerBar: data.beatsPerBar ?? 4,
    };
    setNotes(data.notes.map((n) => ({ t: n.t, s: n.s, f: n.f, d: n.d, finger: n.finger ?? null, fingerAuto: n.finger == null })));
    state.chords = (data.chords ?? []).map((c) => ({ t: c.t, d: c.d, name: c.name })).sort((a, b) => a.t - b.t);
    state.detected = null;
    state.arrange = { mode: 'single', simplify: 0, transpose: 0 };
    undo.length = redo.length = 0;
    state.edited = false;
    openEditor(`${state.notes.length} Noten${state.chords.length ? `, ${state.chords.length} Akkorde` : ''} geladen`);
  } catch (error) {
    alert('Die Datei ist keine gültige Song-Datei:\n' + error.message);
  }
}

/** Set while a recognition runs: stops it. */
let cancelRecognition = null;

/** This page's version (`?v=…`), handed on so every file is the same release. */
const VERSION = new URL(import.meta.url).search;

/** Runs Basic Pitch on the recording, mono at 22 050 Hz as it expects, in a
 * worker on WebAssembly: the page keeps responding, and no graphics card
 * is involved. */
async function transcribe(decoded, progress) {
  const offline = new OfflineAudioContext(1, Math.ceil(decoded.duration * 22050), 22050);
  const source = offline.createBufferSource();
  source.buffer = decoded;
  source.connect(offline.destination);
  source.start();
  const samples = (await offline.startRendering()).getChannelData(0).slice();
  let engine = 'wird gestartet';
  progress(0, engine);
  const worker = new Worker(new URL(`./transcribe.worker.js${VERSION}`, import.meta.url), { type: 'module' });
  try {
    return await new Promise((resolve, reject) => {
      cancelRecognition = () => reject(Object.assign(new Error('Abgebrochen'), { cancelled: true }));
      let last = 0;
      worker.onmessage = ({ data }) => {
        if (data.engine) progress(last, (engine = data.engine));
        else if (data.progress != null) progress((last = data.progress), engine);
        else if (data.error) reject(new Error(data.error));
        else resolve(data.notes);
      };
      worker.onerror = (e) => reject(new Error(e.message || 'Die Notenerkennung konnte nicht starten.'));
      worker.postMessage({ samples }, [samples.buffer]);
    });
  } finally {
    worker.terminate();
  }
}

$('save-json').addEventListener('click', () => {
  readMeta();
  download(new Blob([exportJson()], { type: 'application/json' }), `${state.meta.id || 'song'}.json`);
  state.edited = false;
});
// The tab as it stands, for Guitar Pro; the song file stays the one to keep.
$('save-gp5').addEventListener('click', () => {
  readMeta();
  download(new Blob([exportGp5()], { type: 'application/octet-stream' }), `${state.meta.id || 'song'}.gp5`);
});
function download(blob, name) {
  const link = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: name });
  link.click();
  URL.revokeObjectURL(link.href);
  setStatus(`Gespeichert: ${name}`);
}

const exportGp5 = () => gp5(state.meta, state.notes, state.chords);

function exportJson() {
  return toJson(
    state.meta,
    state.notes.map((n) => ({ t: n.t, s: n.s, f: n.f, d: n.d, finger: n.finger })),
    state.chords,
  );
}
window.yallaStudio = { state, exportJson, exportGp5 }; // for automated tests

// ---------------------------------------------------------------- page

/** A short record of what happened, shown under the progress. */
let steps = [];
function diagnose(reset, step) {
  if (reset) steps = [];
  steps.push(step);
  $('diagnostics').textContent = steps.join(' → ');
}

function browser() {
  const ua = navigator.userAgent;
  const name = /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox' : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'Browser';
  const version = (ua.match(/(?:Edg|Firefox|Chrome|Version)\/(\d+)/) ?? [])[1] ?? '';
  const device = /iPhone|iPad/.test(ua) ? 'iOS' : /Android/.test(ua) ? 'Android' : /Mac/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : 'Linux';
  return `${name} ${version} (${device}) · Studio ${VERSION.replace('?v=', '') || 'dev'}`;
}

/** When the current step started, for the running clock. */
let progressSince = 0, progressClock = null;

function showProgress(text, fraction) {
  if ($('progress').hidden) {
    $('progress-text').classList.remove('error');
    progressSince = Date.now();
    progressClock = setInterval(tickProgress, 1000);
  }
  $('progress').hidden = false;
  $('progress-text').textContent = text;
  $('progress-bar').style.width = `${Math.max(2, Math.round(fraction * 100))}%`;
  $('progress-bar').dataset.fraction = fraction;
  tickProgress();
}
function tickProgress() {
  const seconds = Math.round((Date.now() - progressSince) / 1000);
  $('progress-time').textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  // Tell a slow start from a hang.
  $('progress-hint').hidden = !(seconds > 20 && +$('progress-bar').dataset.fraction < 0.05);
}
const hideProgress = () => {
  $('progress').hidden = true;
  clearInterval(progressClock);
};
$('cancel').addEventListener('click', () => {
  cancelRecognition?.();
  hideProgress();
  setStatus('Abgebrochen');
});
addEventListener('unhandledrejection', (e) => {
  if (!$('progress').hidden && !e.reason?.cancelled) {
    hideProgress();
    alert('Fehler bei der Notenerkennung:\n' + (e.reason?.message ?? e.reason));
  }
});

function openEditor(status) {
  hideProgress();
  $('drop').hidden = true;
  $('editor').hidden = false;
  $('save-json').disabled = false;
  $('save-gp5').disabled = false;
  writeMeta();
  state.selected = -1;
  state.selectedChord = -1;
  state.scroll = 0;
  state.playhead = 0;
  resize();
  inspect();
  setStatus(status);
}

const setStatus = (text) => { $('status').textContent = text; };

function writeMeta() {
  $('title').value = state.meta.title;
  $('artist').value = state.meta.artist;
  $('song-id').value = state.meta.id;
  $('bpm').value = state.meta.bpm;
  $('beats-per-bar').value = state.meta.beatsPerBar;
  $('requantize').disabled = !state.detected;
  writeArrange();
}
function writeArrange() {
  $('bpm').value = state.meta.bpm;
  $('arrange').hidden = !state.detected;
  $('mode').value = state.arrange.mode;
  $('simplify').value = state.arrange.simplify;
  $('transpose').value = state.arrange.transpose;
}
function readMeta() {
  state.meta.title = $('title').value.trim();
  state.meta.artist = $('artist').value.trim();
  state.meta.id = slug($('song-id').value || state.meta.title);
  $('song-id').value = state.meta.id;
  state.meta.beatsPerBar = +$('beats-per-bar').value;
}
$('title').addEventListener('input', () => {
  if (!$('song-id').dataset.touched) $('song-id').value = slug($('title').value);
  state.edited = true;
});
$('song-id').addEventListener('input', () => { $('song-id').dataset.touched = '1'; });
$('artist').addEventListener('input', () => { state.edited = true; });
$('beats-per-bar').addEventListener('change', () => { readMeta(); draw(); });
$('bpm').addEventListener('change', () => {
  const bpm = +$('bpm').value;
  if (!(bpm >= 30 && bpm <= 260)) return writeMeta();
  // The recording stays where it is: tick 0 keeps its time, the grid
  // spacing changes. "Raster neu berechnen" fits the notes to it again.
  state.meta.bpm = bpm;
  draw();
});
$('requantize').addEventListener('click', () => {
  if (!state.detected) return;
  if (state.edited && !confirm('Die Noten werden neu aus der Aufnahme berechnet, deine Korrekturen gehen verloren. Weiter?')) return;
  change(() => {
    state.notes = chartNotes(state.detected, { bpm: state.meta.bpm, offset: state.offset, ticksPerBeat: state.meta.ticksPerBeat, ...state.arrange })
      .map((n) => ({ ...n, fingerAuto: true }));
  });
  setStatus(`Neu berechnet mit ${state.meta.bpm} BPM`);
});

// Recognition mode, simplifying and transposing: the notes come anew from
// what was heard, which an undo brings back.
for (let k = -12; k <= 12; k++) {
  const label = k === 0 ? '0 (Original)' : `${k > 0 ? '+' : '−'}${Math.abs(k)}${Math.abs(k) === 12 ? ' (Oktave)' : ''}`;
  $('transpose').append(new Option(label, k));
}
for (const id of ['mode', 'simplify', 'transpose']) $(id).addEventListener('change', rearrange);
function rearrange() {
  if (!state.detected) return;
  const before = state.arrange;
  const next = { mode: $('mode').value, simplify: +$('simplify').value, transpose: +$('transpose').value };
  let tempoText = '';
  change(() => {
    state.arrange = next;
    if (next.mode !== before.mode) {
      // Another melody may sit on another grid.
      const tempo = detectTempo(pickMelody(state.detected, next.mode), { ticksPerBeat: state.meta.ticksPerBeat });
      if (tempo.bpm !== state.meta.bpm) tempoText = ` · Tempo ${tempo.bpm} BPM`;
      state.meta.bpm = tempo.bpm;
      state.offset = tempo.offset;
    }
    state.notes = chartNotes(state.detected, { bpm: state.meta.bpm, offset: state.offset, ticksPerBeat: state.meta.ticksPerBeat, ...next })
      .map((n) => ({ ...n, fingerAuto: true }));
    const shift = next.transpose - before.transpose;
    if (shift) state.chords = state.chords.map((c) => ({ ...c, name: transposeChord(c.name, shift) }));
    state.selected = -1;
  });
  writeArrange();
  setStatus(`${state.notes.length} Noten${tempoText}`);
}
for (const [id, step] of [['shift-left', -1], ['shift-right', 1]]) {
  $(id).addEventListener('click', () => {
    if (step < 0 && state.notes.some((n) => n.t === 0)) return setStatus('Die erste Note ist schon am Anfang.');
    change(() => { for (const n of state.notes) n.t += step; });
    // The recording moves with the notes, so they still line up.
    state.offset -= step * tickSeconds();
    draw();
  });
}

// ---------------------------------------------------------------- editing

function setNotes(notes) {
  state.notes = notes.sort((a, b) => a.t - b.t || a.s - b.s);
  refinger();
}

/** Fingers left on automatic follow the one-finger-per-fret rule again. */
function refinger() {
  const auto = assignFingers(state.notes.map((n) => n.f));
  state.notes.forEach((n, i) => { if (n.fingerAuto) n.finger = auto[i]; });
}

/** Applies an edit so that it can be undone. */
const snapshot = () => JSON.stringify({
  notes: state.notes, chords: state.chords, selected: state.selected, selectedChord: state.selectedChord,
  arrange: state.arrange, bpm: state.meta.bpm, offset: state.offset,
});

function change(edit) {
  undo.push(snapshot());
  if (undo.length > 200) undo.shift();
  redo.length = 0;
  const selectedNote = state.notes[state.selected];
  const chord = state.chords[state.selectedChord];
  edit();
  setNotes(state.notes);
  state.chords.sort((a, b) => a.t - b.t);
  if (selectedNote) state.selected = state.notes.indexOf(selectedNote);
  if (chord) state.selectedChord = state.chords.indexOf(chord);
  state.edited = true;
  inspect();
  draw();
}
function restore(from, to) {
  if (!from.length) return;
  to.push(snapshot());
  const saved = JSON.parse(from.pop());
  state.notes = saved.notes;
  state.chords = saved.chords ?? [];
  state.selected = Math.min(saved.selected, state.notes.length - 1);
  state.selectedChord = Math.min(saved.selectedChord ?? -1, state.chords.length - 1);
  state.arrange = saved.arrange;
  state.meta.bpm = saved.bpm;
  state.offset = saved.offset;
  writeArrange();
  state.edited = true;
  inspect();
  draw();
}

const selected = () => state.notes[state.selected];

function inspect() {
  const n = selected(), c = state.chords[state.selectedChord];
  $('inspector-empty').hidden = !!(n || c);
  $('inspector-fields').hidden = !n;
  $('chord-fields').hidden = !c;
  if (c) {
    const parts = parseChord(c.name);
    $('chord-name').textContent = c.name;
    $('c-root').value = parts.root;
    $('c-quality').value = parts.quality;
    $('c-bass').value = parts.bass ?? '';
    $('c-tick').value = c.t;
    $('c-length').value = c.d;
  }
  if (!n) return;
  $('note-name').textContent = noteName(midiOf(n.s, n.f));
  $('f-string').value = n.s;
  $('f-fret').value = n.f;
  $('f-tick').value = n.t;
  $('f-length').value = n.d;
  $('f-finger').value = n.fingerAuto ? 'auto' : n.finger;
}

const field = (id, apply) => $(id).addEventListener('change', () => {
  const n = selected();
  if (!n) return;
  const value = $(id).value;
  change(() => apply(n, value));
});
field('f-string', (n, v) => { n.s = +v; });
field('f-fret', (n, v) => { n.f = Math.max(0, Math.min(24, Math.round(+v || 0))); });
field('f-tick', (n, v) => { n.t = Math.max(0, Math.round(+v || 0)); });
field('f-length', (n, v) => { n.d = Math.max(1, Math.round(+v || 1)); });
field('f-finger', (n, v) => {
  n.fingerAuto = v === 'auto';
  if (!n.fingerAuto) n.finger = +v;
});
$('delete').addEventListener('click', () => deleteSelected());
$('other-position').addEventListener('click', () => otherPosition(1));

function deleteSelected() {
  if (!selected()) return;
  change(() => { state.notes.splice(state.selected, 1); });
  state.selected = Math.min(state.selected, state.notes.length - 1);
  inspect();
  draw();
}

/** Moves the note to the next string that plays the same pitch. */
function otherPosition(direction) {
  const n = selected();
  if (!n) return;
  const options = positions(midiOf(n.s, n.f));
  if (options.length < 2) return setStatus('Diesen Ton gibt es nur an einer Stelle.');
  const i = options.findIndex((o) => o.s === n.s);
  const next = options[(i + direction + options.length) % options.length];
  change(() => { n.s = next.s; n.f = next.f; });
}

function addNote(t, s) {
  const before = [...state.notes].reverse().find((n) => n.t <= t);
  const note = { t, s, f: before && before.s === s ? before.f : 0, d: state.meta.ticksPerBeat, finger: null, fingerAuto: true };
  change(() => { state.notes.push(note); });
  state.selected = state.notes.indexOf(note);
  inspect();
  draw();
}

// ---------------------------------------------------------------- chords

const QUALITY_LABELS = {
  '': 'Dur', m: 'Moll', 7: '7', maj7: 'maj7', m7: 'm7', 6: '6', m6: 'm6', dim: 'dim (vermindert)',
  aug: 'aug (übermäßig)', sus2: 'sus2', sus4: 'sus4', add9: 'add9', 9: '9', 5: '5 (Powerchord)',
};
for (const [i, name] of ROOT_NAMES.entries()) {
  $('c-root').add(new Option(name, i));
  $('c-bass').add(new Option(name, i));
}
$('c-bass').add(new Option('wie Grundton', ''), 0);
for (const q of Object.keys(CHORD_QUALITIES)) $('c-quality').add(new Option(QUALITY_LABELS[q] ?? q, q));

const selectedChord = () => state.chords[state.selectedChord];
const chordField = (id, apply) => $(id).addEventListener('change', () => {
  const c = selectedChord();
  if (c) change(() => apply(c, $(id).value));
});
const rename = (c) => {
  const bass = $('c-bass').value;
  c.name = chordName(+$('c-root').value, $('c-quality').value, bass === '' ? null : +bass);
};
chordField('c-root', rename);
chordField('c-quality', rename);
chordField('c-bass', rename);
chordField('c-tick', (c, v) => { c.t = Math.max(0, Math.round(+v || 0)); });
chordField('c-length', (c, v) => { c.d = Math.max(1, Math.round(+v || 1)); });
$('c-delete').addEventListener('click', () => deleteChord());

function deleteChord() {
  if (!selectedChord()) return;
  change(() => { state.chords.splice(state.selectedChord, 1); });
  state.selectedChord = -1;
  inspect();
  draw();
}

/** A new chord on the beat at [tick]: as long as a bar, or up to the next
 * chord; the chord before it, or the key's tonic, to start from. */
function addChord(tick) {
  const { ticksPerBeat, beatsPerBar } = state.meta;
  const t = Math.floor(tick / ticksPerBeat) * ticksPerBeat;
  if (state.chords.some((c) => c.t <= t && t < c.t + c.d)) return;
  const next = state.chords.find((c) => c.t > t);
  const before = [...state.chords].reverse().find((c) => c.t < t);
  const suggested = suggestChords(state.notes, state.meta).find((c) => c.t <= t && t < c.t + c.d);
  const chord = {
    t,
    d: Math.max(1, Math.min(ticksPerBeat * beatsPerBar, (next?.t ?? Infinity) - t)),
    name: suggested?.name ?? before?.name ?? 'C',
  };
  change(() => { state.chords.push(chord); });
  state.selected = -1;
  state.selectedChord = state.chords.indexOf(chord);
  inspect();
  draw();
}

$('suggest-chords').addEventListener('click', () => {
  if (!state.notes.length) return;
  if (state.chords.length && !confirm('Die vorhandenen Akkorde werden durch Vorschläge ersetzt. Weiter?')) return;
  change(() => { state.chords = suggestChords(state.notes, state.meta); });
  state.selectedChord = -1;
  inspect();
  draw();
  setStatus(`${state.chords.length} Akkorde vorgeschlagen, bitte anhören und anpassen`);
});

document.addEventListener('keydown', (e) => {
  if ($('editor').hidden || e.target.matches('input, select')) return;
  const c = selectedChord();
  if (c && !(e.ctrlKey || e.metaKey) && e.key !== ' ' && e.key !== 'Tab') {
    const beat = state.meta.ticksPerBeat;
    const edits = {
      ArrowLeft: () => { c.t = Math.max(0, c.t - beat); },
      ArrowRight: () => { c.t += beat; },
      '[': () => { c.d = Math.max(1, c.d - beat); },
      ']': () => { c.d += beat; },
    };
    if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); deleteChord(); }
    else if (edits[e.key]) { e.preventDefault(); change(edits[e.key]); reveal(c.t); }
    e.stopImmediatePropagation();
  }
}, true);

document.addEventListener('keydown', (e) => {
  if ($('editor').hidden || e.target.matches('input, select')) return;
  const n = selected();
  const key = e.key;
  if ((e.ctrlKey || e.metaKey) && key.toLowerCase() === 'z') { e.preventDefault(); return e.shiftKey ? restore(redo, undo) : restore(undo, redo); }
  if ((e.ctrlKey || e.metaKey) && key.toLowerCase() === 'y') { e.preventDefault(); return restore(redo, undo); }
  if (key === ' ') { e.preventDefault(); return togglePlay(); }
  if (key === 'Tab') {
    e.preventDefault();
    if (!state.notes.length) return;
    state.selected = (state.selected + (e.shiftKey ? -1 : 1) + state.notes.length) % state.notes.length;
    state.selectedChord = -1;
    reveal(selected().t);
    inspect();
    return draw();
  }
  if (!n) return;
  const edits = {
    ArrowLeft: () => { if (n.t > 0) n.t--; },
    ArrowRight: () => { n.t++; },
    '[': () => { if (n.d > 1) n.d--; },
    ']': () => { n.d++; },
    a: () => { n.fingerAuto = true; },
  };
  if (key === 'ArrowUp' || key === 'ArrowDown') {
    e.preventDefault();
    if (e.altKey) return otherPosition(key === 'ArrowUp' ? -1 : 1);
    return change(() => { n.f = Math.max(0, Math.min(24, n.f + (key === 'ArrowUp' ? 1 : -1))); });
  }
  if (key === 'Delete' || key === 'Backspace') { e.preventDefault(); return deleteSelected(); }
  if (/^[0-4]$/.test(key)) return change(() => { n.finger = +key; n.fingerAuto = false; });
  if (edits[key]) { e.preventDefault(); change(edits[key]); reveal(n.t); }
});

// ---------------------------------------------------------------- drawing

const canvas = $('canvas');
const g = canvas.getContext('2d');
const layout = { left: 34, wave: 64, chords: 100, top: 136, gap: 34 };
const stringY = (s) => layout.top + (s - 1) * layout.gap;
const x = (tick) => layout.left + (tick - state.scroll) * state.zoom;
const tickAt = (px) => (px - layout.left) / state.zoom + state.scroll;
let peaks = null;

function resize() {
  const ratio = devicePixelRatio || 1;
  canvas.width = canvas.clientWidth * ratio;
  canvas.height = canvas.clientHeight * ratio;
  g.setTransform(ratio, 0, 0, ratio, 0, 0);
  peaks = null;
  draw();
}
addEventListener('resize', () => { if (!$('editor').hidden) resize(); });

const lastTick = () => Math.max(
  state.notes.reduce((m, n) => Math.max(m, n.t + n.d), 0),
  state.chords.reduce((m, c) => Math.max(m, c.t + c.d), 0),
) + state.meta.ticksPerBeat * state.meta.beatsPerBar;
const visibleTicks = () => (canvas.clientWidth - layout.left) / state.zoom;

function updateScrollbar() {
  const s = $('scroll');
  s.max = Math.max(0, Math.ceil(lastTick() - visibleTicks() + 4));
  s.value = state.scroll;
}
$('scroll').addEventListener('input', (e) => { state.scroll = +e.target.value; draw(); });
$('zoom').addEventListener('input', (e) => { state.zoom = +e.target.value; peaks = null; draw(); });
canvas.addEventListener('wheel', (e) => {
  e.preventDefault();
  const delta = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
  state.scroll = Math.max(0, Math.min(+$('scroll').max, state.scroll + delta / state.zoom));
  draw();
}, { passive: false });

/** Keeps [tick] on screen. */
function reveal(tick) {
  const visible = visibleTicks();
  if (tick < state.scroll + 2 || tick > state.scroll + visible - 4) {
    state.scroll = Math.max(0, tick - visible / 3);
  }
}

/** Loudest sample per pixel column of the recording, for the waveform. */
function wavePeaks(width) {
  if (!state.audio) return null;
  const data = state.audio.getChannelData(0), rate = state.audio.sampleRate;
  const perTick = tickSeconds() * rate;
  const out = new Float32Array(width);
  for (let px = 0; px < width; px++) {
    const from = Math.floor((state.offset + tickAt(px) * tickSeconds()) * rate);
    const to = from + Math.max(1, Math.floor(perTick / state.zoom));
    let max = 0;
    for (let i = Math.max(0, from); i < Math.min(data.length, to); i++) max = Math.max(max, Math.abs(data[i]));
    out[px] = max;
  }
  return out;
}

function draw() {
  if ($('editor').hidden) return;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  g.clearRect(0, 0, w, h);
  updateScrollbar();
  const { ticksPerBeat, beatsPerBar } = state.meta;
  const bar = ticksPerBeat * beatsPerBar;
  const first = Math.floor(state.scroll), last = Math.ceil(state.scroll + visibleTicks());

  // Beats and bars.
  for (let t = Math.floor(first / ticksPerBeat) * ticksPerBeat; t <= last; t += ticksPerBeat) {
    if (t < 0) continue;
    const isBar = t % bar === 0;
    g.strokeStyle = isBar ? 'rgba(242,202,80,.55)' : 'rgba(255,255,255,.07)';
    g.lineWidth = isBar ? 1.5 : 1;
    g.beginPath();
    g.moveTo(x(t), 6);
    g.lineTo(x(t), stringY(6) + 14);
    g.stroke();
    if (isBar) {
      g.fillStyle = '#d0c5af';
      g.font = '11px system-ui';
      g.fillText(String(t / bar + 1), x(t) + 3, layout.wave + 18);
    }
  }

  // The recording, lined up with the grid.
  if (state.audio) {
    if (!peaks || peaks.scroll !== state.scroll || peaks.width !== w) {
      peaks = { data: wavePeaks(w), scroll: state.scroll, width: w };
    }
    const mid = layout.wave / 2 + 4;
    g.fillStyle = 'rgba(208,197,175,.45)';
    for (let px = layout.left; px < w; px++) {
      const a = Math.min(1, peaks.data[px] * 1.6) * (layout.wave / 2 - 4);
      g.fillRect(px, mid - a, 1, 2 * a || 1);
    }
  }

  // The chord lane.
  g.fillStyle = '#d0c5af';
  g.font = 'bold 11px system-ui';
  g.fillText('Akk.', 2, layout.chords + 4);
  g.strokeStyle = 'rgba(255,255,255,.08)';
  g.lineWidth = 1;
  g.beginPath();
  g.moveTo(layout.left - 6, layout.chords);
  g.lineTo(w, layout.chords);
  g.stroke();
  state.chords.forEach((c, i) => {
    if (c.t + c.d < first - 1 || c.t > last + 1) return;
    const x0 = x(c.t) + 1, x1 = Math.max(x(c.t + c.d) - 2, x0 + 30);
    const chosen = i === state.selectedChord;
    g.fillStyle = chosen ? 'rgba(242,202,80,.3)' : 'rgba(242,202,80,.12)';
    roundRect(x0, layout.chords - 13, x1 - x0, 26, 8);
    g.fill();
    g.strokeStyle = chosen ? '#f2ca50' : 'rgba(242,202,80,.55)';
    g.lineWidth = chosen ? 2.5 : 1;
    g.stroke();
    g.fillStyle = '#f2ca50';
    g.font = 'bold 14px system-ui';
    g.fillText(c.name, x0 + 7, layout.chords + 5);
  });

  // Strings.
  for (let s = 1; s <= 6; s++) {
    g.strokeStyle = s >= 4 ? '#b8925a' : '#9a9a9a';
    g.lineWidth = 1 + (s - 1) * 0.3;
    g.beginPath();
    g.moveTo(layout.left - 6, stringY(s));
    g.lineTo(w, stringY(s));
    g.stroke();
    g.fillStyle = '#d0c5af';
    g.font = 'bold 13px system-ui';
    g.fillText(STRING_NAMES[s - 1], 10, stringY(s) + 4);
  }

  // Notes, colored by finger like in the app.
  state.notes.forEach((n, i) => {
    if (n.t + n.d < first - 1 || n.t > last + 1) return;
    const x0 = x(n.t) + 1, x1 = Math.max(x(n.t + n.d) - 2, x0 + 20), y = stringY(n.s);
    g.fillStyle = FINGER_COLORS[n.finger ?? 0];
    g.globalAlpha = i === state.selected ? 1 : 0.85;
    roundRect(x0, y - 11, x1 - x0, 22, 11);
    g.fill();
    g.globalAlpha = 1;
    if (i === state.selected) {
      g.strokeStyle = '#f2ca50';
      g.lineWidth = 3;
      roundRect(x0 - 2, y - 13, x1 - x0 + 4, 26, 13);
      g.stroke();
    }
    g.fillStyle = '#fff';
    g.font = 'bold 13px system-ui';
    g.fillText(String(n.f), x0 + 7, y + 5);
  });

  // Playhead.
  const px = x(state.playhead);
  if (px >= layout.left) {
    g.strokeStyle = '#f2ca50';
    g.lineWidth = 2;
    g.beginPath();
    g.moveTo(px, 0);
    g.lineTo(px, h);
    g.stroke();
  }
}

function roundRect(x0, y0, width, height, r) {
  g.beginPath();
  g.roundRect(x0, y0, width, height, Math.min(r, width / 2));
}

// Clicks: select a note, drag it along, or place the playhead; a double
// click on a string adds a note there.
let drag = null;
canvas.addEventListener('pointerdown', (e) => {
  canvas.focus();
  const { px, py } = point(e);
  const hit = noteAt(px, py), chordHit = chordAt(px, py);
  if (hit >= 0) {
    state.selected = hit;
    state.selectedChord = -1;
    drag = { startTick: tickAt(px), note: state.notes[hit], from: state.notes[hit].t, moved: false };
    canvas.setPointerCapture(e.pointerId);
  } else if (chordHit >= 0) {
    state.selectedChord = chordHit;
    state.selected = -1;
    const chord = state.chords[chordHit];
    drag = { startTick: tickAt(px), note: chord, from: chord.t, moved: false, chord: true };
    canvas.setPointerCapture(e.pointerId);
  } else {
    state.selected = -1;
    state.selectedChord = -1;
    state.playhead = Math.max(0, Math.round(tickAt(px)));
  }
  inspect();
  draw();
});
canvas.addEventListener('pointermove', (e) => {
  if (!drag) return;
  // Chords move by whole beats, notes by steps.
  const step = drag.chord ? state.meta.ticksPerBeat : 1;
  const t = Math.max(0, drag.from + step * Math.round((tickAt(point(e).px) - drag.startTick) / step));
  if (t !== drag.note.t) {
    if (!drag.moved) {
      undo.push(snapshot());
      redo.length = 0;
      drag.moved = true;
    }
    drag.note.t = t;
    draw();
  }
});
canvas.addEventListener('pointerup', () => {
  if (drag?.moved && drag.chord) {
    state.chords.sort((a, b) => a.t - b.t);
    state.selectedChord = state.chords.indexOf(drag.note);
    state.edited = true;
    inspect();
    draw();
  } else if (drag?.moved) {
    const note = drag.note;
    setNotes(state.notes);
    state.selected = state.notes.indexOf(note);
    state.edited = true;
    inspect();
    draw();
  }
  drag = null;
});
canvas.addEventListener('dblclick', (e) => {
  const { px, py } = point(e);
  if (noteAt(px, py) >= 0 || chordAt(px, py) >= 0) return;
  if (Math.abs(py - layout.chords) <= 15) return addChord(Math.max(0, tickAt(px)));
  const s = Math.round((py - layout.top) / layout.gap) + 1;
  if (s >= 1 && s <= 6) addNote(Math.max(0, Math.round(tickAt(px) - 0.5)), s);
});

function point(e) {
  const r = canvas.getBoundingClientRect();
  return { px: e.clientX - r.left, py: e.clientY - r.top };
}
function chordAt(px, py) {
  if (Math.abs(py - layout.chords) > 15) return -1;
  return state.chords.findIndex((c) => px >= x(c.t) && px <= Math.max(x(c.t + c.d) - 2, x(c.t) + 30));
}
function noteAt(px, py) {
  for (let i = state.notes.length - 1; i >= 0; i--) {
    const n = state.notes[i];
    const x0 = x(n.t), x1 = Math.max(x(n.t + n.d) - 2, x0 + 20);
    if (px >= x0 && px <= x1 && Math.abs(py - stringY(n.s)) <= 13) return i;
  }
  return -1;
}

// ---------------------------------------------------------------- playing

$('play').addEventListener('click', () => togglePlay());

const plucks = new Map();
/** Karplus-Strong plucked string, as in the app. */
function pluck(midi) {
  if (plucks.has(midi)) return plucks.get(midi);
  const c = audioContext(), rate = c.sampleRate;
  const buffer = c.createBuffer(1, Math.round(rate * 2), rate);
  const out = buffer.getChannelData(0);
  const period = Math.max(2, Math.round(rate / hz(midi)));
  const line = Array.from({ length: period }, () => Math.random() * 2 - 1);
  for (let i = 1; i < period; i++) line[i] = 0.6 * line[i] + 0.4 * line[i - 1];
  for (let i = 0; i < out.length; i++) {
    const j = i % period;
    out[i] = 0.35 * line[j];
    line[j] = 0.996 * 0.5 * (line[j] + line[(j + 1) % period]);
  }
  plucks.set(midi, buffer);
  return buffer;
}

function togglePlay() {
  if (state.playing) return stop();
  const c = audioContext();
  c.resume();
  const speed = +$('speed').value;
  const start = c.currentTime + 0.08;
  const sources = [];
  if ($('hear-audio').checked && state.audio) {
    if (speed === 1) {
      const src = c.createBufferSource();
      src.buffer = state.audio;
      src.connect(c.destination);
      const at = state.offset + state.playhead * tickSeconds();
      if (at < state.audio.duration) {
        src.start(start + Math.max(0, -at), Math.max(0, at));
        sources.push(src);
      }
    } else {
      setStatus('Die Aufnahme spielt nur bei 100 % mit.');
    }
  }
  if ($('hear-notes').checked) {
    for (const n of state.notes) {
      if (n.t + n.d <= state.playhead) continue;
      const when = start + (n.t - state.playhead) * tickSeconds() / speed;
      const src = c.createBufferSource();
      src.buffer = pluck(midiOf(n.s, n.f));
      const gain = c.createGain();
      gain.gain.setValueAtTime(0.9, Math.max(start, when));
      gain.gain.setTargetAtTime(0, Math.max(start, when) + n.d * tickSeconds() / speed, 0.04);
      src.connect(gain).connect(c.destination);
      src.start(Math.max(start, when), Math.max(0, start - when));
      sources.push(src);
    }
  }
  if ($('hear-chords').checked) {
    for (const ch of state.chords) {
      if (ch.t + ch.d <= state.playhead) continue;
      const parts = parseChord(ch.name);
      if (!parts) continue;
      const when = Math.max(start, start + (ch.t - state.playhead) * tickSeconds() / speed);
      const end = start + (ch.t + ch.d - state.playhead) * tickSeconds() / speed;
      // Soft keys between G3 and F#4 and the bass note below, as in the app.
      const tones = chordTones(parts).map((pc) => 55 + ((pc - 55) % 12 + 12) % 12);
      const bass = 40 + (((parts.bass ?? parts.root) - 40) % 12 + 12) % 12;
      for (const [midi, level] of [...tones.map((m) => [m, 0.07]), [bass, 0.12]]) {
        const osc = c.createOscillator();
        osc.type = 'triangle';
        osc.frequency.value = hz(midi);
        const gain = c.createGain();
        gain.gain.setValueAtTime(0, when);
        gain.gain.linearRampToValueAtTime(level, when + 0.01);
        gain.gain.setTargetAtTime(level * 0.5, when + 0.02, 0.4);
        gain.gain.setTargetAtTime(0, end, 0.05);
        osc.connect(gain).connect(c.destination);
        osc.start(when);
        osc.stop(end + 0.4);
        sources.push(osc);
      }
    }
  }
  state.playing = { sources, start, from: state.playhead, speed };
  $('play').textContent = '⏸';
  requestAnimationFrame(follow);
}

function stop() {
  for (const src of state.playing.sources) { try { src.stop(); } catch { /* already ended */ } }
  state.playing = null;
  $('play').textContent = '▶';
  draw();
}

function follow() {
  if (!state.playing) return;
  const { start, from, speed } = state.playing;
  state.playhead = from + Math.max(0, audioContext().currentTime - start) * speed / tickSeconds();
  if (state.playhead > lastTick()) return stop();
  reveal(state.playhead);
  draw();
  requestAnimationFrame(follow);
}

document.addEventListener('visibilitychange', () => { if (document.hidden && state.playing) stop(); });
addEventListener('beforeunload', (e) => { if (state.edited) e.preventDefault(); });
