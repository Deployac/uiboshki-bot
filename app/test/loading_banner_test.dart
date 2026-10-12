// «Загрузка» (дизайн, второй круг, Никита 12.10): «Без сети» — только когда
// сети правда нет («Нет сети» / «Сервер не отвечает», значок не погодный), и
// тонкая строка «Обновляю · данные от 09:41», пока экран показывает запас
// телефона и ждёт сеть дольше 600 мс. С выключенным design2 — всё как было.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/api.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/main.dart';
import 'package:uiboshki/screens/shell.dart';
import 'package:uiboshki/widgets/common.dart';

import 'fake_api.dart';
import 'look_test.dart' show meta;
import 'util.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  /// «Сегодня» с сегодняшней датой — его запас экран покажет.
  Map<String, Object?> today() => {
    'GET /api/today': Map<String, dynamic>.from(demoFixtures()['GET /api/today'])..['date'] = iso(now()),
  };

  test('подписи плашки: старая и новые', () {
    final day = DateTime(2026, 10, 8, 12);
    expect(OfflineBanner.stamp(DateTime(2026, 10, 8, 9, 41), day), '09:41');
    expect(OfflineBanner.stamp(DateTime(2026, 10, 7, 9, 41), day), 'вчера 09:41');
    expect(OfflineBanner.stamp(DateTime(2026, 10, 7, 9, 41), DateTime(2026, 10, 9)), '7 октября 09:41');
    expect(OfflineBanner.label(DateTime(2026, 10, 8, 9, 5), day), 'Без сети · данные от 09:05');
    expect(OfflineBanner.label(DateTime(2026, 10, 8, 9, 5), day, what: 'Нет сети'), 'Нет сети · данные от 09:05');
  });

  test('таймаут — «сервер не отвечает», обрыв связи — «нет сети»', () async {
    var off = false, slow = false;
    final api = fakeApi(offline: () => off, slow: () => slow);
    await api.get('/me');
    slow = true;
    await api.get('/me');
    expect(api.offlineSince.value, isNotNull);
    expect(api.offlineSlow.value, isTrue);
    slow = false;
    off = true;
    await api.get('/me');
    expect(api.offlineSlow.value, isFalse);
  });

  test('запас отдаёт время самого старого ответа', () async {
    SharedPreferences.setMockInitialValues({
      'uib_cache:/me': jsonEncode({'at': '2026-10-07T09:41:00', 'body': '{"first_name":"Никита"}'}),
      'uib_cache:/today': jsonEncode({'at': '2026-10-08T08:00:00', 'body': '{"lessons":[]}'}),
    });
    final api = fakeApi();
    final r = await Api.fromCacheAt(() async {
      final a = await api.get('/today');
      final b = await api.get('/me');
      return [a, b];
    });
    expect(r?.at, DateTime(2026, 10, 7, 9, 41));
    expect(await Api.fromCacheAt(() => api.get('/files')), isNull); // не загружалось
  });

  test('несколько экранов ждут сеть — время самого старого, все ответили — пусто', () {
    final a = Api.refreshStart(DateTime(2026, 10, 8, 9, 41));
    final b = Api.refreshStart(DateTime(2026, 10, 7, 22, 10));
    expect(Api.refreshing.value, DateTime(2026, 10, 7, 22, 10));
    Api.refreshDone(b);
    expect(Api.refreshing.value, DateTime(2026, 10, 8, 9, 41));
    Api.refreshDone(a);
    Api.refreshDone(a); // второй раз — ничего
    expect(Api.refreshing.value, isNull);
  });

  Future<void> offlineApp(WidgetTester t, {required bool design2, bool slow = false}) async {
    phone(t);
    await loadFonts();
    var off = false;
    final api = fakeApi(
      offline: () => off && !slow,
      slow: () => off && slow,
      overrides: {...today(), ...meta(design2)},
    );
    await api.get('/today');
    off = true;
    await t.pumpWidget(UiboApp(api: api, design2: design2));
    await settle(t);
  }

  testWidgets('новый дизайн: нет сети — «Нет сети» и значок без облака', (t) async {
    await offlineApp(t, design2: true);
    expect(find.textContaining('Нет сети · данные от'), findsOneWidget);
    expect(find.textContaining('Без сети'), findsNothing);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    expect(find.text('сегодня · 5 пар'), findsOneWidget);
  });

  testWidgets('новый дизайн: сервер не ответил вовремя — «Сервер не отвечает»', (t) async {
    await offlineApp(t, design2: true, slow: true);
    expect(find.textContaining('Сервер не отвечает · данные от'), findsOneWidget);
    expect(find.textContaining('Нет сети'), findsNothing);
    expect(find.byIcon(Icons.hourglass_bottom_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
  });

  testWidgets('старый дизайн: «Без сети» с облаком, как было', (t) async {
    await offlineApp(t, design2: false, slow: true);
    expect(find.textContaining('Без сети · данные от'), findsOneWidget);
    expect(find.textContaining('Сервер не отвечает'), findsNothing);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  /// Запас «Сегодня» есть, сеть отвечает через [wait].
  Future<void> slowApp(WidgetTester t, {required bool design2, required Duration wait}) async {
    phone(t);
    var delay = Duration.zero;
    final api = fakeApi(delay: () => delay, overrides: {...today(), ...meta(design2)});
    await api.get('/today');
    delay = wait;
    await t.pumpWidget(UiboApp(api: api, design2: design2));
  }

  /// Дождаться всех медленных ответов (цепочки запросов экранов).
  Future<void> drain(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(seconds: 1));
    }
  }

  final refresh = find.textContaining('Обновляю · данные от');

  testWidgets('медленная сеть: запас сразу, через 600 мс — «Обновляю», пришло — строка ушла', (t) async {
    await slowApp(t, design2: true, wait: const Duration(seconds: 3));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('сегодня · 5 пар'), findsOneWidget); // запас, без крутилки
    expect(refresh, findsNothing); // ещё рано
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 300));
    expect(refresh, findsOneWidget);
    expect(find.textContaining('Без сети'), findsNothing);
    expect(find.textContaining('Нет сети'), findsNothing);
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(refresh, findsNothing);
    expect(Api.refreshing.value, isNull);
    await drain(t);
  });

  testWidgets('быстрая сеть: строка «Обновляю» не мелькает', (t) async {
    await slowApp(t, design2: true, wait: const Duration(milliseconds: 200));
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
      expect(refresh, findsNothing);
    }
    expect(Api.refreshing.value, isNull);
    await drain(t);
  });

  testWidgets('старый дизайн: строки «Обновляю» нет', (t) async {
    await slowApp(t, design2: false, wait: const Duration(seconds: 3));
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
      expect(refresh, findsNothing);
    }
    await drain(t);
  });
}
