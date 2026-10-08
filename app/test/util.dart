import 'package:flutter/widgets.dart';
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
