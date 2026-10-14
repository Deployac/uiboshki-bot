// PWA на телефоне: t.me открывался встроенным браузером поверх приложения и
// оставался белой страницей вместо числа для входа (Никита, 14.10) — там
// сразу tg://. В приложении и на компьютере — обычная ссылка.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/screens/login.dart';

void main() {
  const link = 'https://t.me/uiboshkibot?start=login_abc-DEF_123';

  test('PWA на телефоне — сразу в Telegram', () {
    for (final p in [TargetPlatform.iOS, TargetPlatform.android]) {
      expect(
        botUri(link, web: true, platform: p).toString(),
        'tg://resolve?domain=uiboshkibot&start=login_abc-DEF_123',
      );
    }
  });

  test('приложение и компьютер — t.me', () {
    expect(botUri(link, web: false, platform: TargetPlatform.iOS).toString(), link);
    expect(botUri(link, web: true, platform: TargetPlatform.windows).toString(), link);
    expect(botUri(link, web: true, platform: TargetPlatform.macOS).toString(), link);
  });
}
