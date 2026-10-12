// Изменения в расписании (5.79, Никита 12.10, «изменения» Б и Г): сменили
// кабинет — прежний зачёркнут, рамка; отменили пару — серая, «пары не будет».
// Только в новом дизайне; счёт пар отменённые не меняют.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/screens/today.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/theme/look.dart';

import 'fake_api.dart';
import 'util.dart';

Map<String, Object?> changed() {
  final j = jsonDecode(jsonEncode(demoFixtures()['GET /api/today'])) as Map<String, dynamic>;
  final lessons = j['lessons'] as List;
  final first = lessons.first as Map<String, dynamic>;
  first['room_was'] = 'Г-226 (В-78)';
  first['room_changed_at'] = '09:12';
  j['cancelled'] = [
    {
      'start': '18:00',
      'end': '19:30',
      'title': 'Физическая культура',
      'kind': 'практика',
      'room': '',
      'cancelled_at': '08:40',
    },
  ];
  return {'GET /api/today': j};
}

Future<void> show(WidgetTester t, {required bool design2, Look look = const Look()}) async {
  await t.pumpWidget(
    AppStyle(
      p: Palette.notebook,
      font: FontChoice.book,
      look: look,
      design2: design2,
      child: MaterialApp(
        home: Scaffold(
          body: TodayScreen(api: fakeApi(overrides: changed())),
        ),
      ),
    ),
  );
  await settle(t);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  for (final look in const [Look(), Look(day: DayView.rows)]) {
    testWidgets('сменили кабинет и отменили пару: ${look.day.name}', (t) async {
      phone(t);
      await show(t, design2: true, look: look);
      final list = find.byType(Scrollable).first;
      await t.scrollUntilVisible(find.text('кабинет изменён в 09:12'), 200, scrollable: list);
      expect(find.text('кабинет изменён в 09:12'), findsOneWidget);
      final was = t.widget<Text>(find.text('Г-226 (В-78)'));
      expect(was.style?.decoration, TextDecoration.lineThrough);
      await t.scrollUntilVisible(find.text('Физическая культура'), 200, scrollable: list);
      expect(find.text('пары не будет'), findsOneWidget);
      final title = t.widget<Text>(find.text('Физическая культура'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
    });
  }

  testWidgets('старый дизайн — без отметок, отменённой пары нет', (t) async {
    phone(t);
    await show(t, design2: false);
    expect(find.textContaining('кабинет изменён'), findsNothing);
    expect(find.text('пары не будет'), findsNothing);
    expect(find.text('Физическая культура'), findsNothing);
  });
}
