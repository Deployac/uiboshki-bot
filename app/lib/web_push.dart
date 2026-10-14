// Веб-пуши PWA (веб-сборка на /app): подписка браузера → /api/push/subscribe,
// дальше их шлёт delivery.deliver. В приложении (iPhone, Android) — заглушка:
// там пуши свои (FCM/APNs/RuStore, потом).
import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart' as impl;

/// on / off / denied / install / unsupported (см. window.uibPush в web/index.html).
Future<String> webPushState() => impl.state();

/// Подписка браузера JSON-строкой; '' — человек не разрешил уведомления.
Future<String> webPushEnable(String vapidKey) => impl.enable(vapidKey);

/// Адрес отписанной подписки; '' — подписки не было.
Future<String> webPushDisable() => impl.disable();
