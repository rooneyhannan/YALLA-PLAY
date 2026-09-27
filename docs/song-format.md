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
| `notes` | One object per note, in any order. |
| `chords` | Optional: the backing's chords, in any order. Without them the app picks chords from the melody. |

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

To add a song: put its JSON file into `assets/songs/` and set `chart: '<id>'`
on its entry in `lib/core/models/song.dart`.
