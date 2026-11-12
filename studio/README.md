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
2. Correct the tab: click a note to edit it, drag it along, drag the yellow handles at its ends to make it longer or shorter (chords too, by beats), double-click a string to add
   one; the waveform above shows where the recording plays. Play back the recording,
   the notes or both.
3. **JSON speichern**: a `yalla-song/1` file (see `docs/song-format.md`) for
   `assets/songs/`.

**🎙 Aufnehmen** records straight from the microphone (echo cancelling, noise suppression and
automatic gain are off, so the guitar sounds as it is): a level meter, a choice of input, an
optional three-second count-in, then ● to start and ■ to stop. Listen back, and **OK, umwandeln**
recognises it like an opened file; **Neu aufnehmen** tries again, **Aufnahme speichern** keeps the
raw recording (WebM, or M4A on Safari). Recordings stop by themselves after 15 minutes.
A microphone also hears the guitar body boom at each pluck (around A2) and open bass strings ringing
along; *Eine Stimme* drops those: a low note just after the pluck of a much higher one, the same low
pitch coming with the plucks of many different notes, and quiet notes far under the tune.

Before recognition the recording is high-passed at 65 Hz (rumble under the low E string) and brought
to full level. The Studio also measures in the recording how sharply the sound rises where each note
starts (`withAttacks`): a pluck rises by 7 dB or more, a string swelling as it rings (or a phone
turning its volume up as it fades) by 3 dB or less. The same note again without a pluck is the string
ringing on and lengthens the note before, instead of becoming a new one.

**➕ In die App** puts the song into the Yalla Guitar app's library, under *أغانيّ من الاستوديو*
("my songs from the Studio"), with no new release of the app: the Studio and the app are served from
the same site and so share this browser's storage (`localStorage`, key `yalla.mySongs`, a JSON list of
`yalla-song/1` songs). The song is there on this device and in this browser; the app removes it with
the bin on its card. A song for everyone still goes into `assets/songs/`.

**🎼 Guitar Pro öffnen** (or dropping a file) reads a Guitar Pro 7/8 file (`.gp`: a ZIP archive with
`Content/score.gpif`, XML) with `gpread.js`. A file with several guitar tracks asks which one.
The track's tune (the highest note of each beat), fingers, chord diagrams' names and tempo come in;
grace notes, muted notes and drums are left out, repeats are read as written. Standard tuning without
capo keeps the file's strings and frets; another tuning or a capo is laid out anew for standard tuning.
The grid is sixteenths, or finer where triplets need it. Older formats (`.gpx`, `.gp3`–`.gp5`) are not read.

**JSON öffnen** loads a song file again for editing.

**Guitar Pro** saves the tab as it stands as a Guitar Pro 5 file (`.gp5`), which Guitar Pro 5–8,
TuxGuitar, MuseScore and Songsterr open: one guitar track in standard tuning with frets, fingers,
the chords over the beats and the key signature. Held notes go on as tied notes. Titles are written
in plain letters (Arabic spelt in Latin ones), as the format has no Unicode.

- `transcribe.js`: melody, tempo, grid, tab and fingers; pure functions.
- `gpread.js`: the `.gp` reader (ZIP, a small XML reader, the score, one track as a song).
- `guitarpro.js`: the `.gp5` writer, byte for byte as PyGuitarPro writes version 5.10
  (`test/*.gp5` are its reference files).
- `studio.js`: the page. `transcribe.worker.js`: Basic Pitch in a worker on WebAssembly (no graphics card needed), falling back to the processor.
- `vendor/`: Basic Pitch and its model (Apache 2.0).
- Tests: `node --test 'studio/test/*.test.mjs'`.
