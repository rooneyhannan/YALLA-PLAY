# Song requests from Notion

Rooney asks for songs in the Notion database **Song-Wünsche** (Titel,
Interpret, Hinweis). Claude turns one request into a song like this:

1. **Source.** Find the melody in a source anyone can check: sheet music,
   an ABC or MusicXML transcription, a tab. Note its link in the request's
   **Quelle**. Melody only, never lyrics. A song still under copyright, or
   one without such a source, goes to **Problem** with the reason.
2. **Chart.** Write the melody as a `yalla-song/1` file (see
   `song-format.md`) at the source's pitch and metre: string and fret by
   the Studio's `assignTab`, `ticksPerBeat` and `beatsPerBar` from the
   time signature. Recorded songs go through Yalla Studio instead.
3. **Check.** Compare the file note by note with the source by a script,
   not by eye (in ABC an accidental holds to the end of its bar).
4. **App.** Put the file into `assets/songs/` and set `chart: '<id>'` on
   the song's entry in `lib/core/models/song.dart`, adding the entry when
   the song is new. Open a pull request and merge it once the
   "Flutter review build" check is green; GitHub Pages then has the song
   a few minutes later. The request goes to **Bitte prüfen**, with the
   pull request in **Ergebnis**.
5. Once Rooney has heard it, the request goes to **In der App**.

The first one: `lamma-bada.json`, „لما بدا يتثنى“, from the ABC by Tous aux
Balkans on abcnotation.com.
