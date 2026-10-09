// Своё приложение называет себя серверу (X-App) — в боте «Войти… на Капибара · iPhone».
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/api/api.dart';

void main() {
  test('X-App: ios / android по платформе', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(Api.platform, 'ios');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(Api.platform, 'android');
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(Api.platform, isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
