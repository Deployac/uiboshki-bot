import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/main.dart';
import 'package:uiboshki/screens/shell.dart';

import 'fake_api.dart';
import 'util.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  test('без сети — последний ответ из памяти, выход стирает', () async {
    var off = false;
    final api = fakeApi(offline: () => off);
    final fresh = await api.get('/me');
    expect(api.offlineSince.value, isNull);
    off = true;
    final cached = await api.get('/me');
    expect(cached, fresh);
    expect(api.offlineSince.value, isNotNull);
    await expectLater(api.get('/files'), throwsA(anything)); // не загружалось — нечего показать
    await api.logout();
    await expectLater(api.get('/me'), throwsA(anything));
    expect(api.offlineSince.value, isNull);
  });

  test('подпись плашки', () {
    final today = DateTime(2026, 10, 8, 12);
    expect(OfflineBanner.label(DateTime(2026, 10, 8, 9, 5), today), 'Без сети · данные от 09:05');
    expect(OfflineBanner.label(DateTime(2026, 10, 7, 22, 10), today), 'Без сети · данные от вчера 22:10');
    expect(OfflineBanner.label(DateTime(2026, 10, 1, 8, 0), today), 'Без сети · данные от 1 октября 08:00');
  });

  testWidgets('приложение без сети показывает сохранённое и плашку', (t) async {
    phone(t);
    var off = false;
    final api = fakeApi(offline: () => off);
    await api.get('/today'); // была сеть — ответ сохранён
    off = true;
    await t.pumpWidget(UiboApp(api: api));
    await settle(t);
    expect(find.textContaining('Без сети · данные от'), findsOneWidget);
    expect(find.text('сегодня · 5 пар'), findsOneWidget); // пары из сохранённого ответа
  });
}
