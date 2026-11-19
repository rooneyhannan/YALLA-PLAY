# Song format `yalla-song/1`

Songs live as JSON files in `assets/songs/<id>.json`. Yalla Studio
(`studio/`) writes them; the app reads them when a song opens.

```json
{
  "format": "yalla-song/1",
  "id": "badak",
  "title": "Ba’dak Ala Bali",
  "artist": "فيروز",
  "bpm": 90,
  "ticksPerBeat": 4,
  "beatsPerBar": 4,
  "backing": {"guitar": "both", "rhythm": "maqsum", "darbuka": true},
  "notes": [
    {"t": 0, "s": 2, "f": 3, "d": 4, "finger": 1}
  ],
  "chords": [
    {"t": 0, "d": 16, "name": "Dm"}
  ]
}
```

| Field | Meaning |
|---|---|
| `format` | Always `yalla-song/1`. |
| `id` | File name without `.json`; the song list refers to it. |
| `title`, `artist` | Shown in the app. `artist` may be empty. |
| `bpm` | Beats per minute at normal speed. |
| `ticksPerBeat` | The smallest step of the song; 4 means sixteenth notes in 4/4. Default 4. |
| `beatsPerBar` | Beats per bar, for bar lines and the metronome's stress. Default 4. |
| `maqam` | Optional: the maqam Yalla Studio heard in the melody, as in `D Nahawand` (Ajam, Nahawand, Kurd or Hijaz on a tonic). For information; the app does not read it yet. |
| `backing` | Optional: how the app accompanies the song, set in Yalla Studio under **🥁 Begleitung in der App**; see below. Left out, or any field of it, the defaults apply. |
| `notes` | One object per note, in any order. |
| `chords` | Optional: the backing's chords, in any order. Yalla Studio fills them in from the melody's maqam when a song comes in without any. A file without them the app still harmonizes by major or minor key. |

Each note:

| Field | Meaning |
|---|---|
| `t` | Start, in ticks from the beginning of the song. Gaps between notes are rests. |
| `s` | String, 1 = high E … 6 = low E, standard tuning. |
| `f` | Fret, 0 = open string, up to 24. |
| `d` | Length in ticks, at least 1. |
| `finger` | Optional: 1 index … 4 pinky, 0 open string. Left out, the app picks fingers by the one-finger-per-fret rule. |

The pitch follows from string and fret; the microphone listens for that pitch.

Each chord:

| Field | Meaning |
|---|---|
| `t` | Start, in ticks. Where no chord sounds, the backing rests. |
| `d` | Length in ticks, at least 1. |
| `name` | Root `C` … `B` with `#` or `b`, then a type: none (major), `m`, `7`, `maj7`, `m7`, `6`, `m6`, `dim`, `aug`, `sus2`, `sus4`, `add9`, `9`, `5`; optionally `/` and a bass note, as in `C/E`. |

The backing never plays the pitch the player is asked for at that moment, in
any octave, so the microphone hears only the guitar for it.

The backing:

| Field | Values (default first) |
|---|---|
| `guitar` | `both` (one guitar strums, another picks the chord note by note at the same time), `strum`, `arpeggio`, `off`. |
| `rhythm` | `auto` (Maqsum in 4/4, Sama'i in 10/8, a plain one otherwise), `maqsum` (D T k T D k T k), `baladi` (D D k T D k T k), `saidi` (D T k D D k T k), `wahda` (D k k T k k T k), `samai` (D k k T k D D k T k, ten steps). |
| `darbuka` | `true` or `false`: whether a darbuka plays the rhythm. |

The rhythm runs on eighths in 4/4 and similar metres and on beats in long
bars such as 10/8: `D` is the doum, the deep stroke, `T` the tek, the bright
one, `k` a soft ka between them. A named rhythm that does not fit the bar
gives way to a plain one (doum on the one, teks on the even steps). The
strumming guitar strikes on every step, all six strings down on a doum,
firm on a tek and light up and down in between; the darbuka plays the same
pattern. The last bar rings out on one strummed chord and one doum. A bass
plays the chord's bass note on the first beat and its fifth halfway through
the bar, strings hold the chord underneath, and a second and third voice
sing under long melody notes.

Yalla Studio can open the app's songs (**📚 Song aus der App**) and keep a
changed one in the browser's storage (`yalla.songEdits`); the app on that
device then plays it instead of the file here.

To add a song: put its JSON file into `assets/songs/` and set `chart: '<id>'`
on its entry in `lib/core/models/song.dart`.
