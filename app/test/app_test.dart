import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/main.dart';
import 'package:uiboshki/screens/shell.dart';
import 'package:uiboshki/screens/week.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/capy.dart';

import 'fake_api.dart';

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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  testWidgets('без токена — экран входа через бота', (t) async {
    await t.pumpWidget(UiboApp(api: fakeApi(token: null)));
    await settle(t);
    expect(find.text('Войти через Telegram'), findsOneWidget);
    expect(find.text('УИБО'), findsOneWidget);
  });

  testWidgets('с токеном — вкладки, капсула переключает экраны', (t) async {
    final asked = <String>[];
    phone(t);
    await t.pumpWidget(UiboApp(api: fakeApi(requests: asked)));
    await settle(t);
    expect(asked, contains('GET /api/today'));
    // выбранная вкладка подписана, остальные — значки
    expect(find.text('Сегодня'), findsWidgets);
    await t.tap(find.bySemanticsLabel('Сдать'));
    await settle(t);
    expect(asked, contains('GET /api/deadlines?include_done=true'));
    expect(find.text('Сдать'), findsWidgets);
    await t.tap(find.bySemanticsLabel('Ещё'));
    await settle(t);
    expect(find.text('Аня'), findsOneWidget); // имя из /api/me
    expect(find.text('УИБО-03-24'), findsOneWidget); // группа из профиля, не из настроек
  });

  testWidgets('шрифт переключается и запоминается', (t) async {
    await t.pumpWidget(UiboApp(api: fakeApi()));
    await settle(t);
    await t.tap(find.bySemanticsLabel('Ещё'));
    await settle(t);
    await t.tap(find.text('Строгий'));
    await settle(t);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('uib_font'), 'strict');
  });

  testWidgets('первый запуск — знакомство «Что где», один раз', (t) async {
    SharedPreferences.setMockInitialValues({});
    phone(t);
    await t.pumpWidget(UiboApp(api: fakeApi()));
    await settle(t);
    expect(find.text('Что где'), findsOneWidget);
    await t.tap(find.text('Понятно'));
    await settle(t);
    expect(find.text('Что где'), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('uib_toured'), isTrue);
  });

  test('вкладка из ссылки пуша', () {
    expect(tabByName('deadlines'), 2);
    expect(tabByName('sdo'), 3);
    expect(tabByName(null), 0);
  });

  test('капибара по времени суток', () {
    expect(moodAt(8), CapyMood.morning);
    expect(moodAt(14), CapyMood.day);
    expect(moodAt(20), CapyMood.evening);
    expect(moodAt(2), CapyMood.night);
  });

  test('сроки и числа по-русски', () {
    expect(leftText(const Duration(hours: 13, minutes: 2)), '13 ч 02 мин');
    expect(leftText(const Duration(days: 3)), '3 дня');
    expect(leftText(const Duration(minutes: -1)), 'срок прошёл');
    expect(plural(21, 'день', 'дня', 'дней'), 'день');
    expect(plural(12, 'день', 'дня', 'дней'), 'дней');
    expect(mondayOf(DateTime(2026, 10, 11)), DateTime(2026, 10, 5));
    expect(dayTitle(DateTime(2026, 10, 8)), 'Четверг, 8 октября');
  });

  test('цвет предмета один и тот же', () {
    expect(subjectColor('Анализ данных'), subjectColor('анализ данных'));
  });

  test('пара из ответа API', () {
    final l = Lesson.fromJson({
      'start': '09:00',
      'end': '10:30',
      'title': 'Анализ данных',
      'kind': 'лекция',
      'room': 'А-17 (В-78)',
      'start_iso': '2026-10-08T09:00:00+03:00',
    });
    expect(l.place, 'Лекция · А-17 (В-78)');
    expect(l.startAt, isNotNull);
  });

  testWidgets('неделя: тема телефона — тёмная «Глубина»', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await t.pumpWidget(UiboApp(api: fakeApi()));
    await settle(t);
    final ctx = t.element(find.byType(Scaffold).first);
    expect(AppStyle.of(ctx).p.dark, isTrue);
    await t.tap(find.bySemanticsLabel('Неделя'));
    await settle(t);
    expect(find.text('Неделя'), findsWidgets);
  });
}
