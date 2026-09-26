# Working on Yalla Guitar

## Workflow the owner asked for

- Deliver every change completely: branch, commit, push, open a pull request,
  wait for the "Flutter review build" check, then **merge the pull request
  yourself** as soon as the check is green. Do not ask the owner to merge.
- If the check fails, fix it and push again before merging.
- Reply to the owner in German.

## Build and publish

- Flutter 3.47.2. Checks: `dart format lib test`, `flutter analyze --no-fatal-infos`, `flutter test`.
- GitHub Pages serves the repository root of `main`. Rebuild and copy the web
  app there with `tool/build_web.sh --publish` and commit the result together
  with source changes; merging then updates https://rooneyhannan.github.io/YALLA-PLAY/.
- The script stamps the build (shown in the tuner footer) and versions the
  loaded scripts so a reload shows the new release despite GitHub Pages caching.
- Restore generated noise before committing: `git checkout -- build android ios`.
