#!/bin/sh
# Веб-сборка приложения (app/) для PWA на /app → webapp/flutter (её отдаёт
# webapp/server.py). Запускает GitHub Actions после мержа (app-web.yml);
# руками — то же самое, нужен Flutter в PATH.
set -e
cd "$(dirname "$0")/../app"
# --no-web-resources-cdn: canvaskit — со своего сервера, не с CDN Google
# (из России и без «КВН» он должен открываться)
flutter build web --release --base-href /app/ --dart-define=API= --no-web-resources-cdn --no-wasm-dry-run
out=../webapp/flutter
rm -rf "$out"
cp -r build/web "$out"
cd "$out"
# лишнее для сборки на JS: отладочные символы, движки для --wasm, свой
# service worker и иконки Flutter (у PWA — /sw.js и /pwa/…)
rm -rf icons canvaskit/webparagraph flutter_service_worker.js manifest.json favicon.png .last_build_id
rm -f canvaskit/skwasm* canvaskit/wimp*
find canvaskit -name '*.symbols' -delete
