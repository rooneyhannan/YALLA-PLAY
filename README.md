# Yalla Guitar

Arabic guitar-learning Flutter prototype based on the four supplied Stitch designs.

## App

- Responsive dashboard, song library, learning path, and tuner screens.
- Arabic RTL layout, bundled IBM Plex Sans Arabic fonts, and bundled design images.
- Search and session favorites; every song opens the six-string guitar preview.
- Pause, restart, playback speed, and frame-independent note animation.
- The original Ba’dak Ala Bali note chart is retained. Other songs explicitly use a demo chart.
- Microphone detection and scoring are not connected. The tuner is a visual/manual selection preview.
- Course progress, points, premium labels, and trial banners are design examples. No purchases or accounts are created.

## Run

Use Flutter 3.47.2:

```sh
flutter pub get
flutter run -d chrome
```

## Review

```sh
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --base-href /YALLA-PLAY/ --no-web-resources-cdn
```

GitHub Actions runs analysis, behavior tests, and a web build without requiring a local Flutter installation. It also exports mobile and desktop design previews as workflow artifacts. On the design branch, the successful workflow commits the web output back to the branch so merging the reviewed PR updates the existing GitHub Pages site (configured for `main` / root).

To export layout review images locally:

```sh
flutter test --dart-define=CAPTURE_PREVIEWS=true --update-goldens test/design_preview_test.dart
```

Images are exported to `test/previews/`. These exports are visual review aids, not preapproved golden baselines.

## Assets

`assets/design/sources.json` records image URLs from the user-supplied Stitch export. The retained assets are bundled for reliable rendering. Some artist/album imagery in that export is illustrative. The font license is in `assets/fonts/OFL.txt`.
