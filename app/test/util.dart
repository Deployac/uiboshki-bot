import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Экран телефона, а не 800×600 по умолчанию.
void phone(WidgetTester t) {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Настоящие шрифты приложения: у тестового «квадратного» другая ширина.
Future<void> loadFonts() async {
  Future<void> one(String family, String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await l.load();
  }

  await one('Onest', 'assets/fonts/Onest.ttf');
  await one('SourceSerif', 'assets/fonts/SourceSerif4.ttf');
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/home/user/sdk/flutter';
  await one('MaterialIcons', '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}
