// Yalla Studio: open a recording, let Basic Pitch find its notes, turn them
// into a guitar tab, correct it by hand and save it as a yalla-song/1 file.
import {
  assignFingers, chartNotes, detectTempo, fromJson, hz, melodyOf, midiOf,
  noteName, positions, slug, toJson,
} from './transcribe.js';

const $ = (id) => document.getElementById(id);
const FINGER_COLORS = ['#9aa0a6', '#4f8bff', '#3ed8e8', '#a27bff', '#e860c0'];
const STRING_NAMES = ['e', 'B', 'G', 'D', 'A', 'E'];

/** Everything the page edits. */
const state = {
  meta: { id: '', title: '', artist: '', bpm: 90, ticksPerBeat: 4, beatsPerBar: 4 },
  /** {t, s, f, d, finger, fingerAuto} */
  notes: [],
  /** What Basic Pitch heard, kept to fit the grid again with a new tempo. */
  detected: null,
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
    const melody = melodyOf(detected);
    if (!melody.length) throw new Error('In der Aufnahme wurden keine Gitarrennoten gefunden.');
    const tempo = detectTempo(melody, { ticksPerBeat: 4 });
    const title = file.name.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' ');
    state.meta = { id: slug(title), title, artist: '', bpm: tempo.bpm, ticksPerBeat: 4, beatsPerBar: 4 };
    state.offset = tempo.offset;
    setNotes(chartNotes(detected, { ...tempo, ticksPerBeat: 4 }).map((n) => ({ ...n, fingerAuto: true })));
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
    state.detected = null;
    undo.length = redo.length = 0;
    state.edited = false;
    openEditor(`${state.notes.length} Noten geladen`);
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
  const blob = new Blob([exportJson()], { type: 'application/json' });
  const link = Object.assign(document.createElement('a'), {
    href: URL.createObjectURL(blob), download: `${state.meta.id || 'song'}.json`,
  });
  link.click();
  URL.revokeObjectURL(link.href);
  state.edited = false;
  setStatus(`Gespeichert: ${link.download}`);
});

function exportJson() {
  return toJson(state.meta, state.notes.map((n) => ({ t: n.t, s: n.s, f: n.f, d: n.d, finger: n.finger })));
}
window.yallaStudio = { state, exportJson }; // for automated tests

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
  writeMeta();
  state.selected = -1;
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
    state.notes = chartNotes(state.detected, { bpm: state.meta.bpm, offset: state.offset, ticksPerBeat: state.meta.ticksPerBeat })
      .map((n) => ({ ...n, fingerAuto: true }));
  });
  setStatus(`Neu berechnet mit ${state.meta.bpm} BPM`);
});
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
function change(edit) {
  undo.push(JSON.stringify({ notes: state.notes, selected: state.selected }));
  if (undo.length > 200) undo.shift();
  redo.length = 0;
  const selectedNote = state.notes[state.selected];
  edit();
  setNotes(state.notes);
  if (selectedNote) state.selected = state.notes.indexOf(selectedNote);
  state.edited = true;
  inspect();
  draw();
}
function restore(from, to) {
  if (!from.length) return;
  to.push(JSON.stringify({ notes: state.notes, selected: state.selected }));
  const snapshot = JSON.parse(from.pop());
  state.notes = snapshot.notes;
  state.selected = Math.min(snapshot.selected, state.notes.length - 1);
  state.edited = true;
  inspect();
  draw();
}

const selected = () => state.notes[state.selected];

function inspect() {
  const n = selected();
  $('inspector-empty').hidden = !!n;
  $('inspector-fields').hidden = !n;
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
const layout = { left: 34, wave: 64, top: 96, gap: 34 };
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

const lastTick = () => state.notes.reduce((m, n) => Math.max(m, n.t + n.d), 0) + state.meta.ticksPerBeat * state.meta.beatsPerBar;
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
  const hit = noteAt(px, py);
  if (hit >= 0) {
    state.selected = hit;
    drag = { startTick: tickAt(px), note: state.notes[hit], from: state.notes[hit].t, moved: false };
    canvas.setPointerCapture(e.pointerId);
  } else {
    state.selected = -1;
    state.playhead = Math.max(0, Math.round(tickAt(px)));
  }
  inspect();
  draw();
});
canvas.addEventListener('pointermove', (e) => {
  if (!drag) return;
  const t = Math.max(0, drag.from + Math.round(tickAt(point(e).px) - drag.startTick));
  if (t !== drag.note.t) {
    if (!drag.moved) {
      undo.push(JSON.stringify({ notes: state.notes, selected: state.selected }));
      redo.length = 0;
      drag.moved = true;
    }
    drag.note.t = t;
    draw();
  }
});
canvas.addEventListener('pointerup', () => {
  if (drag?.moved) {
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
  if (noteAt(px, py) >= 0) return;
  const s = Math.round((py - layout.top) / layout.gap) + 1;
  if (s >= 1 && s <= 6) addNote(Math.max(0, Math.round(tickAt(px) - 0.5)), s);
});

function point(e) {
  const r = canvas.getBoundingClientRect();
  return { px: e.clientX - r.left, py: e.clientY - r.top };
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
