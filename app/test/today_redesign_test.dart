// «Сегодня» по выбору владельца (09.10): главный вид 21А — группа с неделей и
// погода одной строкой, приветствие с именем; во время пары 21В — «до конца»
// и где следующая; пары карточками с номером пары; второй вид 22А — дни
// недели, переключатель значками на одном месте, выбор запоминается, свайп
// листает дни.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/screens/lesson.dart';
import 'package:uiboshki/screens/today.dart';
import 'package:uiboshki/screens/week.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/common.dart';

import 'fake_api.dart';
import 'util.dart';

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Map<String, Object?> _lesson(DateTime start, Object num, String title, String room) {
  final end = start.add(const Duration(minutes: 90));
  return {
    'num': num,
    'start': _hm(start),
    'end': _hm(end),
    'title': title,
    'kind': 'практика',
    'room': room,
    'teacher': 'Зорина Н. В.',
    'groups': '',
    'status': '',
    'start_iso': start.toIso8601String(),
    'end_iso': end.toIso8601String(),
  };
}

const _weather = '🌤 +4°, переменная облачность, ощущается +2° · 🧣 куртка не помешает';

/// Ответы: «Сегодня» с данными парами, имя и группа, 6 неделя.
Map<String, Object?> _answers(List<Map<String, Object?>> lessons, {Map<String, Object?> days = const {}}) => {
  'GET /api/today': {
    'lessons': lessons,
    'tomorrow_first': null,
    'weather': _weather,
    'deadlines': {'active': 0, 'soon': []},
  },
  'GET /api/me': {
    'id': 1,
    'first_name': 'Никита',
    'group': {'id': 4928, 'name': 'УИБО-03-24', 'own': true},
  },
  'GET /api/week?start=${iso(mondayOf(now()))}': {'week': 6, 'days': []},
  ...days,
};

Widget _wrap(Widget child) => AppStyle(
  p: Palette.depth,
  font: FontChoice.book,
  child: MaterialApp(
    home: Scaffold(body: SafeArea(child: child)),
  ),
);

void main() {
  setUpAll(loadFonts); // ширина шапки — настоящими шрифтами, как на телефоне
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('погода коротко и без эмодзи; номер пары из API', () {
    final w = weatherBrief(_weather)!;
    expect(w.temp, '+4°');
    expect(w.sky, 'облачно');
    expect(w.full, '+4°, переменная облачность, ощущается +2° · куртка не помешает');
    expect(weatherBrief('🌧 -3°, лёгкий дождь, ощущается -7° · 🧤 перчатки')!.sky, 'дождь');
    expect(weatherBrief(''), isNull);
    expect(Lesson.fromJson({'num': 4}).number, '4');
    expect(Lesson.fromJson({'num': '1–5'}).number, '1–5');
    expect(Lesson.fromJson({}).number, '');
    expect(spanText(134), '2 ч 14 мин');
    expect(spanText(45), '45 мин');
    expect(splitRoom('А-332 (МП-1), Б-304 (МП-1)'), (code: 'А-332, Б-304', campus: 'МП-1'));
  });

  testWidgets('до пар: группа с неделей и погода в одной строке, ниже — приветствие с именем', (t) async {
    phone(t);
    final start = now().add(const Duration(hours: 2, minutes: 5));
    final api = fakeApi(
      overrides: _answers([_lesson(start, 4, 'Объектно-ориентированный анализ и программирование', 'А-332 (МП-1)')]),
    );
    await t.pumpWidget(_wrap(TodayScreen(api: api)));
    await settle(t);
    final group = find.text('УИБО-03-24 · 6 неделя');
    final weather = find.text('+4° облачно');
    expect(group, findsOneWidget);
    expect(weather, findsOneWidget);
    expect((t.getCenter(group).dy - t.getCenter(weather).dy).abs(), lessThan(1)); // одна строка
    final hello = find.text('${greeting(now().hour)},\nНикита');
    expect(hello, findsOneWidget);
    expect(t.getTopLeft(hello).dy, greaterThan(t.getBottomLeft(group).dy));
    expect(find.text('первая пара в'), findsOneWidget);
    expect(find.text('А-332'), findsOneWidget); // плашка кабинета
    expect(find.text('корпус МП-1'), findsOneWidget);
    expect(find.text('2 ч 05 мин'), findsOneWidget);
    expect(find.textContaining('🌤'), findsNothing);

    await t.tap(weather); // погода целиком — по нажатию, тоже без эмодзи
    await t.pump();
    expect(find.text(weatherBrief(_weather)!.full), findsOneWidget);
  });

  testWidgets('во время пары: «до конца», полоска и где следующая', (t) async {
    phone(t);
    final at = now();
    final next = _lesson(at.add(const Duration(minutes: 97)), 5, 'Моделирование бизнес-процессов', 'Б-304 (МП-1)');
    Future<void> show(String nextRoom) async {
      final api = fakeApi(
        overrides: _answers([
          _lesson(at.subtract(const Duration(minutes: 23)), 4, 'Объектно-ориентированный анализ', 'А-332 (МП-1)'),
          {...next, 'room': nextRoom},
        ]),
      );
      await t.pumpWidget(_wrap(TodayScreen(key: UniqueKey(), api: api)));
      await settle(t);
    }

    await show('Б-304 (МП-1)');
    expect(find.text('Идёт первая пара'), findsOneWidget);
    expect(find.text('до конца'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(find.text('дальше в ${next['start']}'), findsOneWidget);
    expect(find.text('Б-304'), findsOneWidget);
    expect(find.text('тот же корпус'), findsOneWidget);
    // карточка идущей пары: «идёт · ещё…», номер залит
    expect(find.text('идёт · ещё 1 ч 07 мин'), findsOneWidget);
    expect(t.widget<PairBadge>(find.widgetWithText(PairBadge, '4')).live, isTrue);
    expect(t.widget<PairBadge>(find.widgetWithText(PairBadge, '5')).live, isFalse);

    await show('Б-304 (В-78)');
    expect(find.text('другой корпус, В-78'), findsOneWidget);
  });

  testWidgets('пары — отдельными карточками с номером пары справа', (t) async {
    phone(t);
    final at = now();
    final api = fakeApi(
      overrides: _answers([
        _lesson(at.add(const Duration(hours: 1)), 4, 'Анализ данных', 'ИВЦ-126 (В-78)'),
        _lesson(at.add(const Duration(hours: 3)), '5–6', 'Архитектура предприятия', 'А-223 (В-78)'),
      ]),
    );
    await t.pumpWidget(_wrap(TodayScreen(api: api)));
    await settle(t);
    expect(find.text('сегодня · 2 пары'), findsOneWidget);
    expect(find.byType(LessonCard), findsNWidgets(2));
    expect(find.descendant(of: find.byType(LessonCard), matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: find.byType(LessonCard), matching: find.text('5–6')), findsOneWidget);
    expect(find.descendant(of: find.byType(LessonCard), matching: find.text('ИВЦ-126 · В-78')), findsOneWidget);
    await t.tap(find.byType(LessonCard).first); // нажал карточку — экран пары
    await settle(t);
    expect(find.byType(LessonScreen), findsOneWidget);
  });

  testWidgets('переключатель: дни недели, на том же месте, запоминается; свайп — соседний день', (t) async {
    phone(t);
    final monday = mondayOf(now());
    final ti = now().weekday - 1;
    Map<String, Object?> day(int i) =>
        _lesson(monday.add(Duration(days: i, hours: 10)), i + 1, 'Предмет: ${weekdays[i]}', 'А-${100 + i} (МП-1)');
    final api = fakeApi(
      overrides: _answers(
        [day(ti)],
        days: {
          for (var i = 0; i < 7; i++)
            'GET /api/day?date=${iso(monday.add(Duration(days: i)))}': {
              'lessons': [day(i)],
            },
        },
      ),
    );
    await t.pumpWidget(_wrap(TodayScreen(api: api)));
    await settle(t);
    expect(find.text('Эта неделя'), findsNothing);
    final where = t.getRect(find.byTooltip('Дни недели'));

    await t.tap(find.byTooltip('Дни недели'));
    await settle(t);
    expect(find.text('Эта неделя'), findsOneWidget);
    expect(find.text('6 неделя'), findsOneWidget);
    expect(t.getRect(find.byTooltip('Дни недели')), where); // переключатель не сдвинулся
    expect((await SharedPreferences.getInstance()).getString(TodayScreen.viewKey), 'days');
    // открыт сегодняшний день, у пары — номер
    expect(find.text('сегодня · 1 пара'), findsOneWidget);
    final today = find.text('Предмет: ${weekdays[ti]}');
    expect(today, findsOneWidget);
    expect(find.descendant(of: find.byType(LessonCard), matching: find.text('${ti + 1}')), findsOneWidget);

    // свайп вбок — соседний день (в субботу и воскресенье — назад)
    final k = ti < 5 ? 1 : -1;
    await t.fling(today, Offset(-400.0 * k, 0), 1500);
    await settle(t);
    expect(find.text('Предмет: ${weekdays[ti + k]}'), findsOneWidget);
    expect(find.text('Предмет: ${weekdays[ti]}'), findsNothing);

    // нажал плитку — её день
    await t.tap(find.byKey(ValueKey('day:${iso(monday)}')));
    await settle(t);
    expect(find.text('Предмет: ${weekdays[0]}'), findsOneWidget);

    // заново открытый экран — сразу в днях недели; обратно — сводка дня
    await t.pumpWidget(_wrap(TodayScreen(key: UniqueKey(), api: api)));
    await settle(t);
    expect(find.text('Эта неделя'), findsOneWidget);
    await t.tap(find.byTooltip('Сводка дня'));
    await settle(t);
    expect(find.text('Эта неделя'), findsNothing);
    expect(find.byKey(const ValueKey('today:main')), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString(TodayScreen.viewKey), 'main');
  });
}
