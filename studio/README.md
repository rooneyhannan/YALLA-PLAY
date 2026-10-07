# Yalla Studio

Turns a guitar recording into a song file for the Yalla Guitar app.

Open <https://rooneyhannan.github.io/YALLA-PLAY/studio/> in a desktop browser:

1. **Aufnahme öffnen**: an MP3/WAV/M4A. Choose *Eine Stimme* for one guitar playing the
   melody, or *Ganzer Song* for a tune within accompaniment: then the Studio follows the
   main line (loud, high, small steps) through chords and bass. Basic Pitch (Spotify,
   runs in the browser) finds the notes; the Studio keeps the melody, finds the tempo,
   puts the notes on the grid and chooses strings, frets and fingers.
   In the editor, **Erkennung**, **Vereinfachen** (grace notes off, or strongly: short
   notes and repeats too) and **Transponieren** (folded by octaves into the guitar)
   compute the notes anew from what was heard; Ctrl+Z undoes it.
2. Correct the tab: click a note to edit it, drag it along, double-click a string to add
   one; the waveform above shows where the recording plays. Play back the recording,
   the notes or both.
3. **JSON speichern**: a `yalla-song/1` file (see `docs/song-format.md`) for
   `assets/songs/`.

**JSON öffnen** loads a song file again for editing.

- `transcribe.js`: melody, tempo, grid, tab and fingers; pure functions.
- `studio.js`: the page. `transcribe.worker.js`: Basic Pitch in a worker on WebAssembly (no graphics card needed), falling back to the processor.
- `vendor/`: Basic Pitch and its model (Apache 2.0).
- Tests: `node --test 'studio/test/*.test.mjs'`.
