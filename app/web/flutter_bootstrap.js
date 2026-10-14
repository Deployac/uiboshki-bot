// Загрузчик веб-сборки (PWA на /app). Свой, а не стандартный: стандартный
// регистрирует flutter_service_worker.js, а у PWA свой /sw.js (оффлайн и пуши,
// webapp/static/sw.js) — два service worker'а мешали бы друг другу.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
