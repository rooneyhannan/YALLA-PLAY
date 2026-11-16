# Working on Yalla Guitar

## Workflow the owner asked for

- Deliver every change completely: branch, commit, push, open a pull request,
  wait for the "Flutter review build" check, then **merge the pull request
  yourself** as soon as the check is green. Do not ask the owner to merge.
- If the check fails, fix it and push again before merging.
- Reply to the owner in German.

## Build and publish

- Flutter 3.47.2. Checks: `dart format lib test`, `flutter analyze --no-fatal-infos`, `flutter test`.
- GitHub Pages serves the repository root of `main`. You do not build it
  yourself: on every push to `main` the "Flutter review build" workflow runs
  `tool/build_web.sh --publish` and commits the web app to the root with
  `[skip ci]`. Merging therefore updates https://rooneyhannan.github.io/YALLA-PLAY/
  a few minutes later. Commit only source changes; do not commit the built
  files (`main.dart.js`, `index.html`, `canvaskit`, …) in a pull request.
- The script stamps the build (shown in the tuner footer) and versions the
  loaded scripts so a reload shows the new release despite GitHub Pages caching.
- Restore generated noise before committing: `git checkout -- build android ios`.

## Songs and Yalla Studio

- Songs are `yalla-song/1` JSON files in `assets/songs/` (see `docs/song-format.md`);
  a song in `lib/core/models/song.dart` plays its file through `chart: '<id>'`.
- `studio/` is a separate static page (served at `/YALLA-PLAY/studio/`): recording
  → Basic Pitch (vendored in `studio/vendor/`) → tab → editor → JSON.
  Its logic lives in `studio/transcribe.js`; test it with `node --test 'studio/test/*.test.mjs'`.

