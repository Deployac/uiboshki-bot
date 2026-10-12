// Виджеты рабочего стола (второй круг дизайна, 12.10): снимок для виджета
// из «Сегодня» и «Сдать», и что при выключенном новом дизайне он стирается.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/main.dart';
import 'package:uiboshki/screens/look_screen.dart';
import 'package:uiboshki/screens/today.dart';
import 'package:uiboshki/widget_data.dart';

import 'fake_api.dart';
import 'util.dart';

/// Канал к телефону понарошку: что писали и стирали, сколько виджетов «стоит».
class FakeSink implements WidgetSink {
  final ops = <String>[];
  final saved = <Map<String, dynamic>>[];
  final int widgets;
  FakeSink({this.widgets = 0});

  @override
  Future<void> save(String json) async {
    ops.add('save');
    saved.add(jsonDecode(json) as Map<String, dynamic>);
  }

  @override
  Future<void> clear() async => ops.add('clear');

  @override
  Future<int> installed() async => widgets;
}

Map<String, Object?> meta(bool on) => {
  'GET /api/meta': {
    'api': 1,
    'server': '5.79.0',
    'min_client': {'web': '0.0.0', 'android': '0.0.0', 'ios': '0.0.0'},
    'login': ['telegram'],
    'features': {'groups': true, 'sessions': true, 'offline': true, 'design2': on},
    'links': {'bot': 'https://t.me/UiboshkiBot'},
  },
};

int ms(String isoTime) => DateTime.parse(isoTime).millisecondsSinceEpoch;

/// «Сегодня» из записи стенда (четверг 8 октября, пять пар).
TodayData demoToday() {
  final j = demoFixtures()['GET /api/today'] as Map<String, dynamic>;
  return TodayData(
    [for (final l in j['lessons'] as List) Lesson.fromJson(Map<String, dynamic>.from(l))],
    Lesson.fromJson(Map<String, dynamic>.from(j['tomorrow_first'])),
    const [],
    '',
  );
}

void main() {
  late WidgetSink? real;
  setUp(() {
    real = HomeWidgets.sink;
    SharedPreferences.setMockInitialValues({'uib_toured': true});
  });
  tearDown(() async {
    await HomeWidgets.clear(); // память «последних пар» между тестами не тянем
    HomeWidgets.sink = real;
  });

  test('снимок из «Сегодня»: пары с моментами, кабинет без корпуса, завтра — первая пара', () {
    final at = DateTime.parse('2026-10-08T10:07:00+03:00');
    final snap = widgetSnapshot(at: at, date: '2026-10-08', data: demoToday());
    expect(snap['v'], widgetSnapshotVersion);
    expect(snap['at'], at.millisecondsSinceEpoch);
    final days = snap['days'] as List;
    expect(days, hasLength(2));
    final today = days[0] as Map;
    expect(today['d'], '2026-10-08');
    expect(today['h'], 'ЧТ, 8 ОКТ · 5 ПАР');
    expect(today['part'], isFalse);
    final first = (today['l'] as List).first as Map;
    expect(first, {
      's': '09:00',
      'e': '10:30',
      'sa': ms('2026-10-08T09:00:00+03:00'),
      'ea': ms('2026-10-08T10:30:00+03:00'),
      't': 'Моделирование бизнес-процессов',
      'r': 'А-17',
      'k': 'лекция',
    });
    final tomorrow = days[1] as Map;
    expect(tomorrow['d'], '2026-10-09');
    expect(tomorrow['h'], 'ПТ, 9 ОКТ'); // знаем только первую пару — без счёта
    expect(tomorrow['part'], isTrue);
    expect(((tomorrow['l'] as List).single as Map)['r'], 'А-332');
    // уходит в канал строкой JSON
    expect(jsonDecode(jsonEncode(snap)), isA<Map>());
  });

  test('завтра целиком, если догрузили; пар нет — так и пишем', () {
    final data = demoToday();
    final at = DateTime.parse('2026-10-08T10:07:00+03:00');
    final full = widgetSnapshot(
      at: at,
      date: '2026-10-08',
      data: data,
      tomorrow: [data.tomorrowFirst!, data.lessons[4]],
    );
    expect(((full['days'] as List)[1] as Map)['h'], 'ПТ, 9 ОКТ · 2 ПАРЫ');
    expect(((full['days'] as List)[1] as Map)['part'], isFalse);
    final empty = widgetSnapshot(at: at, date: '2026-10-08', data: TodayData(const [], null, const [], ''));
    expect(((empty['days'] as List)[0] as Map)['h'], 'ЧТ, 8 ОКТ · ПАР НЕТ');
    expect(((empty['days'] as List)[1] as Map)['h'], 'ПТ, 9 ОКТ · ПАР НЕТ');
    expect(((empty['days'] as List)[1] as Map)['part'], isFalse);
    // месяц и год переходят
    expect(nextDate('2026-12-31'), '2027-01-01');
  });

  test('без start_iso время пары — по Москве; отменённых пар на виджете нет', () {
    const l = Lesson(
      start: '10:40',
      end: '12:10',
      title: 'Анализ данных',
      kind: 'практика',
      room: '',
      teacher: '',
      status: '',
    );
    expect(widgetLesson(l, '2026-10-08')['sa'], ms('2026-10-08T10:40:00+03:00'));
    expect(widgetLesson(l, '2026-10-08')['ea'], ms('2026-10-08T12:10:00+03:00'));
    const gone = Lesson(
      start: '12:40',
      end: '14:10',
      title: 'X',
      kind: '',
      room: '',
      teacher: '',
      status: '',
      cancelled: true,
    );
    expect(widgetDay('2026-10-08', [l, gone])['l'], hasLength(1));
  });

  test('горящий срок: ближайший несданный, не прошедший, до трёх суток', () {
    final at = DateTime.parse('2026-10-08T10:00:00+03:00');
    Deadline d(int id, String s, String date, String time, {bool done = false}) =>
        Deadline(id: id, subject: s, dueDate: date, dueTime: time, done: done);
    final list = [
      d(1, 'Тест 2 · Учетная деятельность (Зач)', '2026-10-01', '18:00'), // прошёл
      d(2, 'Практика 2 · Анализ данных (Экз)', '2026-10-08', '23:00', done: true), // сдан
      d(3, 'Лаба 3 · Архитектура предприятия', '2026-10-08', '23:00'),
      d(4, 'Реферат', '2026-10-09', ''),
      d(5, 'Курсовая', '2026-10-20', '12:00'), // далеко
    ];
    expect(hotDeadline(list, at), {'t': 'Лаба 3', 'due': ms('2026-10-08T23:00:00+03:00')});
    expect(hotDeadline(list.sublist(3), at), {'t': 'Реферат', 'due': ms('2026-10-09T23:59:00+03:00')});
    expect(hotDeadline([list[0], list[1], list[4]], at), isNull);
  });

  testWidgets('новый дизайн включён — «Сегодня» пишет снимок; виджет стоит — догружает завтра', (t) async {
    phone(t);
    final sink = HomeWidgets.sink = FakeSink(widgets: 1);
    final requests = <String>[];
    await t.pumpWidget(
      UiboApp(
        api: fakeApi(overrides: meta(true), requests: requests),
        design2: true,
      ),
    );
    await settle(t);
    expect(sink.ops, isNotEmpty);
    expect(sink.ops.last, 'save');
    final snap = sink.saved.last;
    final days = snap['days'] as List;
    expect((days[0] as Map)['d'], '2026-10-08');
    expect((days[0] as Map)['l'], hasLength(5));
    expect(requests, contains('GET /api/day?date=2026-10-09'));
    expect((days[1] as Map)['part'], isFalse); // завтра целиком
  });

  testWidgets('виджета нет — за завтра не ходим, только первая пара', (t) async {
    phone(t);
    final sink = HomeWidgets.sink = FakeSink();
    await t.pumpWidget(UiboApp(api: fakeApi(overrides: meta(true)), design2: true));
    await settle(t);
    expect(sink.ops.last, 'save');
    expect(((sink.saved.last['days'] as List)[1] as Map)['part'], isTrue);
  });

  testWidgets('сервер выключил новый дизайн — снимок стирается и не пишется', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({'uib_toured': true, 'uib_design2': false});
    final sink = HomeWidgets.sink = FakeSink(widgets: 1);
    await t.pumpWidget(UiboApp(api: fakeApi(overrides: meta(false))));
    await settle(t);
    expect(sink.ops, contains('clear'));
    expect(sink.saved, isEmpty);
    // и «Сдать» тоже ничего не пишет
    await HomeWidgets.fromDeadlines([
      Deadline(id: 1, subject: 'Лаба', dueDate: iso(DateTime.now().add(const Duration(days: 1))), dueTime: '12:00'),
    ]);
    expect(sink.saved, isEmpty);
  });

  testWidgets('выключили, пока приложение работало: последнее — стирание', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({'uib_toured': true, 'uib_design2': true});
    final sink = HomeWidgets.sink = FakeSink();
    await t.pumpWidget(UiboApp(api: fakeApi(overrides: meta(false)), design2: true));
    await settle(t);
    expect(sink.ops.last, 'clear');
  });

  test('«Сдать» без известных пар снимок не пишет, с ними — обновляет срок', () async {
    final sink = HomeWidgets.sink = FakeSink();
    final soon = DateTime.now().add(const Duration(hours: 5));
    final hm = '${soon.toUtc().add(const Duration(hours: 3)).hour.toString().padLeft(2, '0')}:00';
    final dl = Deadline(
      id: 3,
      subject: 'Лаба 3 · Архитектура предприятия',
      dueDate: iso(soon.toUtc().add(const Duration(hours: 3))),
      dueTime: hm,
    );
    await HomeWidgets.fromDeadlines([dl]);
    expect(sink.ops, isEmpty);
    await HomeWidgets.fromToday(fakeApi(), '2026-10-08', demoToday());
    expect(sink.saved.last['dl'], isNull);
    await HomeWidgets.fromDeadlines([dl]);
    expect((sink.saved.last['dl'] as Map)['t'], 'Лаба 3');
    expect((sink.saved.last['days'] as List), hasLength(2));
  });

  testWidgets('«Оформление»: внизу одна строка про виджеты', (t) async {
    phone(t);
    HomeWidgets.sink = FakeSink();
    await t.pumpWidget(UiboApp(api: fakeApi(overrides: meta(true)), design2: true));
    await settle(t);
    await t.tap(find.bySemanticsLabel('Ещё'));
    await settle(t);
    await t.tap(find.text('Оформление'));
    await settle(t);
    final hint = find.textContaining('Виджеты: долгое нажатие');
    final list = find.descendant(of: find.byType(LookScreen), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(hint, 300, scrollable: list);
    expect(hint, findsOneWidget);
  });
}
