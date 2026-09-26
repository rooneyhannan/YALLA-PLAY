#!/usr/bin/env bash
# Builds the web app for GitHub Pages. With --publish, also copies the build
# to the repository root, which GitHub Pages serves.
set -euo pipefail
cd "$(dirname "$0")/.."

build="$(date -u +%Y-%m-%d.%H%M)"
flutter build web --release --base-href /YALLA-PLAY/ --no-web-resources-cdn \
  --dart-define=APP_BUILD="$build"

# GitHub Pages lets browsers cache every file for ten minutes, and a reload
# only revalidates the page itself. Versioning the scripts the page loads
# makes a reload fetch the app that belongs to the page.
out=build/web
sed -i "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?v=$build\"|" \
  "$out/flutter_bootstrap.js"
sed -i "s|src=\"flutter_bootstrap.js\"|src=\"flutter_bootstrap.js?v=$build\"|" \
  "$out/index.html"
grep -q "main.dart.js?v=$build" "$out/flutter_bootstrap.js"
grep -q "flutter_bootstrap.js?v=$build" "$out/index.html"

if [[ "${1:-}" == "--publish" ]]; then
  cp -R "$out/." .
  touch .nojekyll
fi
echo "Built web app $build"
