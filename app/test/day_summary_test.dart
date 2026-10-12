// Итоги дня (5.79, Никита 12.10, А+Г): на прошедших днях после пар —
// «Сводка за день», сколько пар, что сдал и сколько баллов. Пустой день — без
// карточки; только в новом дизайне; в обоих видах «Недели».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/screens/week.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/common.dart';

import 'fake_api.dart';
import 'util.dart';

const _summary = {
  'done': [
    {'title': 'Лабораторная 3'},
  ],
  'grades': [
    {'name': 'Анализ данных', 'delta': 6.0},
  ],
  'points': 6.0,
};

/// Прошлая неделя целиком: в понедельник две пары (одна сдвоенная), остальные дни пустые.
Map<String, Object?> _lastWeek({bool summary = true}) {
  final monday = mondayOf(now()).subtract(const Duration(days: 7));
  final mon = iso(monday);
  Map<String, Object?> lesson(String start, String end, String title, int pairs) => {
    'num': '1',
    'pairs': pairs,
    'start': start,
    'end': end,
    'title': title,
    'kind': 'практика',
    'room': 'А-17',
    'teacher': '',
    'status': '',
    'start_iso': '${mon}T$start:00+03:00',
    'end_iso': '${mon}T$end:00+03:00',
  };
  return {
    for (var i = 1; i < 7; i++) 'GET /api/day?date=${iso(monday.add(Duration(days: i)))}': {'lessons': []},
    'GET /api/day?date=$mon': {
      'lessons': [lesson('09:00', '12:10', 'Анализ данных', 2), lesson('12:40', '14:10', 'Архитектура', 1)],
      'summary': ?(summary ? _summary : null),
    },
  };
}

Future<void> _show(WidgetTester t, {required bool design2, bool summary = true}) async {
  await t.pumpWidget(
    AppStyle(
      p: Palette.notebook,
      font: FontChoice.book,
      design2: design2,
      child: MaterialApp(
        home: Scaffold(
          body: WeekScreen(
            api: fakeApi(overrides: _lastWeek(summary: summary)),
          ),
        ),
      ),
    ),
  );
  await settle(t);
  await t.tap(find.byTooltip('Прошлая неделя'));
  await settle(t);
}

void main() {
  for (final view in ['list', 'days']) {
    group('вид $view', () {
      setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true, WeekScreen.viewKey: view}));

      testWidgets('прошедший день: карточка итога после пар', (t) async {
        phone(t);
        await _show(t, design2: true);
        final card = find.byType(DaySummaryCard);
        await t.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).last);
        expect(card, findsOneWidget);
        expect(find.text('Сводка за день'), findsOneWidget);
        expect(find.text('Лабораторная 3'), findsOneWidget);
        expect(find.text('Анализ данных: +6'), findsOneWidget);
        // 3 пары (сдвоенная — две), 1 сдано, +6 баллов
        final line = find.descendant(of: card, matching: find.byType(RichText));
        final texts = [for (final e in line.evaluate()) (e.widget as RichText).text.toPlainText()];
        expect(texts, containsAll(['3 пары', '1 сдано', '+6 баллов']));
        // карточка — ниже пар дня
        final lastLesson = t.getRect(find.text('Архитектура').last);
        expect(t.getRect(card).top, greaterThan(lastLesson.bottom));
      });

      testWidgets('без итога в ответе — карточки нет', (t) async {
        phone(t);
        await _show(t, design2: true, summary: false);
        expect(find.text('Архитектура'), findsWidgets);
        expect(find.byType(DaySummaryCard, skipOffstage: false), findsNothing);
      });

      testWidgets('старый дизайн — карточки нет', (t) async {
        phone(t);
        await _show(t, design2: false);
        expect(find.text('Архитектура'), findsWidgets);
        expect(find.byType(DaySummaryCard, skipOffstage: false), findsNothing);
        expect(find.text('Сводка за день', skipOffstage: false), findsNothing);
      });
    });
  }

  testWidgets('сегодня — только когда пары кончились; будущее — никогда', (t) async {
    final at = now();
    final today = DateTime(at.year, at.month, at.day);
    Lesson ends(DateTime end) =>
        Lesson(start: '', end: '', title: 'Пара', kind: '', room: '', teacher: '', status: '', endAt: end);
    final sum = DaySummary.fromJson(_summary);
    WeekData week(List<Lesson> lessons) => WeekData(
      null,
      mondayOf(at),
      {iso(today): lessons},
      summaries: {iso(today): sum, iso(today.add(const Duration(days: 1))): sum},
    );
    final got = <String, DaySummary?>{};
    await t.pumpWidget(
      AppStyle(
        p: Palette.notebook,
        font: FontChoice.book,
        design2: true,
        child: Builder(
          builder: (context) {
            got['кончились'] = week([ends(at.subtract(const Duration(minutes: 1)))]).summaryFor(context, today, at);
            got['идут'] = week([ends(at.add(const Duration(hours: 1)))]).summaryFor(context, today, at);
            got['без пар'] = week([]).summaryFor(context, today, at);
            got['завтра'] = week([]).summaryFor(context, today.add(const Duration(days: 1)), at);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(got['кончились'], same(sum));
    expect(got['идут'], isNull);
    expect(got['без пар'], same(sum));
    expect(got['завтра'], isNull);
  });

  test('числа итога: без лишнего нуля, минус типографский', () {
    expect(DaySummaryCard.signed(6), '+6');
    expect(DaySummaryCard.signed(4.5), '+4,5');
    expect(DaySummaryCard.signed(-2), '−2');
    final s = DaySummary.fromJson(_summary);
    expect(s.done, ['Лабораторная 3']);
    expect(s.grades.single, ('Анализ данных', 6.0));
    expect(DaySummary.fromJson(const {'done': [], 'grades': []}).isEmpty, isTrue);
  });
}
