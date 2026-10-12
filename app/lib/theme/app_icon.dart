// Иконка приложения на выбор (5.79, второй круг дизайна, Никита 12.10) —
// как в Telegram: меняется без переустановки. Android — activity-alias на
// каждую (MainActivity.kt), iOS — альтернативные иконки (AppDelegate.swift),
// картинки — tools/app_icons.py. Канал «uiboshki/icon»; на вебе и в тестах
// его нет — тихо ничего не делаем.
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Варианты: «Обычная» — нынешняя иконка, по умолчанию.
enum AppIcon { classic, depth, indigo, terracotta, page, sunset, library }

extension AppIconInfo on AppIcon {
  String get label => switch (this) {
    AppIcon.classic => 'Обычная',
    AppIcon.depth => 'Глубина',
    AppIcon.indigo => 'Индиго',
    AppIcon.terracotta => 'Терракота',
    AppIcon.page => 'Из-за страницы',
    AppIcon.sunset => 'Закат',
    AppIcon.library => 'Библиотека',
  };

  /// Цвет капибары — как на самой иконке.
  Color get capy => switch (this) {
    AppIcon.classic => const Color(0xFFFFF8EE),
    AppIcon.terracotta => const Color(0xFFF3EEE5),
    AppIcon.page => const Color(0xFF2A2721),
    AppIcon.library => const Color(0xFFB9DCA3),
    _ => const Color(0xFFFFFFFF),
  };

  /// Фон иконки (для образца в «Оформлении»).
  Decoration get background => switch (this) {
    // нынешняя: индиго с градиентом из левого верхнего угла
    AppIcon.classic => const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7B7EF4), Color(0xFF4B4FD6)],
      ),
    ),
    AppIcon.depth => const BoxDecoration(color: Color(0xFF141823)),
    AppIcon.indigo => const BoxDecoration(color: Color(0xFF5B5FE0)),
    AppIcon.terracotta => const BoxDecoration(color: Color(0xFFB75438)),
    AppIcon.page => const BoxDecoration(color: pagePaper),
    // 160° как в CSS: концы линии — так, чтобы углы квадрата попали в 0 и 1
    AppIcon.sunset => const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment(-0.438, -1.205),
        end: Alignment(0.438, 1.205),
        colors: [Color(0xFFF2994A), Color(0xFFB75438), Color(0xFF5B3A8F)],
        stops: [0, 0.6, 1],
      ),
    ),
    AppIcon.library => const BoxDecoration(color: Color(0xFF111715)),
  };
}

/// «Из-за страницы»: бумага и терракотовая линия по краю листа.
const pagePaper = Color(0xFFF3EEE5);
const pageLine = Color(0xFFB75438);

const _channel = MethodChannel('uiboshki/icon');

/// Меняется ли иконка на этом устройстве: только Android и iPhone/iPad.
bool get appIconSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Поставить иконку [want], если на телефоне стоит другая. Нет канала
/// (веб, тесты, старая сборка) или система отказала — молча ничего.
Future<void> syncAppIcon(AppIcon want) async {
  if (!appIconSupported) return;
  try {
    final have = await _channel.invokeMethod<String>('getIcon');
    if ((have ?? AppIcon.classic.name) == want.name) return;
    await _channel.invokeMethod<void>('setIcon', want == AppIcon.classic ? null : want.name);
  } on MissingPluginException {
    // канала нет — и не надо
  } on PlatformException {
    // iOS без альтернативных иконок, Android не дал переключить
  }
}
