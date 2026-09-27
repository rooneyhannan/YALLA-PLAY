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

Each note:

| Field | Meaning |
|---|---|
| `t` | Start, in ticks from the beginning of the song. Gaps between notes are rests. |
| `s` | String, 1 = high E … 6 = low E, standard tuning. |
| `f` | Fret, 0 = open string, up to 24. |
| `d` | Length in ticks, at least 1. |
| `finger` | Optional: 1 index … 4 pinky, 0 open string. Left out, the app picks fingers by the one-finger-per-fret rule. |

The pitch follows from string and fret; the microphone listens for that pitch.

To add a song: put its JSON file into `assets/songs/` and set `chart: '<id>'`
on its entry in `lib/core/models/song.dart`.
