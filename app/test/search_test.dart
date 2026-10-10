import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/api.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/main.dart';
import 'package:uiboshki/screens/search.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

/// Ответ /api/target: две недели от текущей, пары только на следующей.
Map<String, Object?> targetFixture({bool pinned = false}) {
  final t = DateTime.now();
  final monday = DateTime(t.year, t.month, t.day).subtract(Duration(days: t.weekday - 1));
  Map<String, Object?> week(int w, Map<int, List> lessons) => {
    'monday': iso(monday.add(Duration(days: 7 * w))),
    'week': 6 + w,
    'days': [
      for (var i = 0; i < 7; i++) {'date': iso(monday.add(Duration(days: 7 * w + i))), 'lessons': lessons[i] ?? []},
    ],
  };
  return {
    'type': 2,
    'id': 77,
    'title': 'Морозов В. А.',
    'pinned': pinned,
    'today': iso(t),
    'stale': null,
    'weeks': [
      week(0, {}),
      week(1, {
        1: [
          {
            'start': '10:40',
            'end': '12:10',
            'title': 'Теория вероятностей',
            'kind': 'практика',
            'room': 'Б-404 (МП-1)',
            'groups': 'УИБО-03-24',
          },
        ],
      }),
    ],
  };
}

String searchKey(String q, int type) => 'GET /api/search?q=${Uri.encodeQueryComponent(q)}&type=$type';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  test('пустые дни подряд — одной строкой «Пн–Ср — пар нет», сегодня отдельно', () {
    Map<String, Object> day(int d, [bool busy = false]) => {
      'date': iso(DateTime(2026, 10, 5 + d)),
      'lessons': busy ? [{}] : [],
    };
    String show(List days, String today) => [
      for (final r in emptyRuns(days, today))
        r.empty ? emptyDaysText(r.from, r.to) : weekdaysShort[r.from.weekday - 1],
    ].join(' | ');
    // Пн–Ср пусто, Чт пары, Пт пусто, Сб пары, Вс пусто — воскресенья нет
    final week = [day(0), day(1), day(2), day(3, true), day(4), day(5, true), day(6)];
    expect(show(week, '2026-09-01'), 'Пн–Ср — пар нет | Чт | Пт — пар нет | Сб');
    // сегодня (вторник) пусто — своим днём, с «сегодня» в подписи
    expect(show(week, '2026-10-06'), 'Пн — пар нет | Вт | Ср — пар нет | Чт | Пт — пар нет | Сб');
  });

  testWidgets('поиск открывается с курсором в поле', (t) async {
    phone(t);
    await t.pumpWidget(
      AppStyle(
        p: Palette.notebook,
        font: FontChoice.book,
        child: MaterialApp(home: SearchScreen(api: fakeApi())),
      ),
    );
    await settle(t);
    expect(t.widget<TextField>(find.byType(TextField)).autofocus, isTrue);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(), isNotNull);
  });

  testWidgets('неделя → поиск: закреплённые, однофамильцы, фильтр, расписание на недели', (t) async {
    phone(t);
    final asked = <String>[];
    final api = fakeApi(
      requests: asked,
      overrides: {
        searchKey('Морозов', 0): {
          'items': [
            {'type': 2, 'id': 77, 'title': 'Морозов В. А.', 'hint': 'Теория вероятностей'},
            {'type': 2, 'id': 78, 'title': 'Морозов В. А.', 'hint': 'Физкультура'},
          ],
          'ready': true,
        },
        searchKey('Морозов', 3): {'items': [], 'ready': true},
        'GET /api/target/2/77': targetFixture(),
      },
    );
    await t.pumpWidget(UiboApp(api: api));
    await settle(t);
    await t.tap(find.bySemanticsLabel('Неделя'));
    await settle(t);
    await t.tap(find.byTooltip('Поиск расписания'));
    await settle(t);
    expect(find.text('Закреплённые'), findsOneWidget); // с сервера, видны с любого устройства
    expect(find.text('Кудрявцева Ирина Геннадьевна'), findsOneWidget);

    await t.enterText(find.byType(EditableText), 'Морозов');
    await settle(t);
    expect(asked, contains(searchKey('Морозов', 0)));
    expect(find.text('Морозов В. А.'), findsNWidgets(2));
    expect(find.text('Преподаватель · Физкультура'), findsOneWidget); // подсказка однофамильца

    await t.ensureVisible(find.text('Аудитории')); // фильтр листается вбок
    await t.pumpAndSettle();
    await t.tap(find.text('Аудитории'));
    await settle(t);
    expect(asked, contains(searchKey('Морозов', 3)));
    expect(find.text('Ничего не нашлось'), findsOneWidget);
    await t.ensureVisible(find.text('Все'));
    await t.pumpAndSettle();
    await t.tap(find.text('Все'));
    await settle(t);

    await t.tap(find.text('Преподаватель · Теория вероятностей'));
    await settle(t);
    expect(asked, contains('GET /api/target/2/77'));
    expect(find.text('преподаватель'), findsNothing); // без курсивной подписи над именем (2.4)
    expect(find.text('Следующая неделя'), findsOneWidget); // ближайший день с парами
    expect(find.text('7 неделя'), findsOneWidget);
    expect(find.text('Теория вероятностей'), findsOneWidget);
    expect(find.textContaining('УИБО-03-24'), findsOneWidget); // чьи это пары

    await t.tap(find.byTooltip('Неделя раньше'));
    await settle(t);
    expect(find.text('Эта неделя'), findsOneWidget);
    expect(find.textContaining('— пар нет'), findsWidgets); // пустые дни — сжаты в строку (2.5)
    expect(find.text('Теория вероятностей'), findsNothing);

    await t.tap(find.byTooltip('Закрепить'));
    await settle(t);
    expect(asked, contains('PUT /api/pins/2/77'));
    expect(find.text('Закреплено — будет сверху в поиске'), findsOneWidget);
    await t.tap(find.byTooltip('Открепить'));
    await settle(t);
    expect(asked, contains('DELETE /api/pins/2/77'));
    expect(find.byTooltip('Закрепить'), findsOneWidget);
  });

  testWidgets('старый ответ не перетирает новый; закрепил — сверху поиска, открыл — в недавних', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({});
    final asked = <String>[];
    final puts = <String, Object?>{};
    var pins = <Map<String, Object?>>[];
    final client = MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1/', '/api/');
      asked.add('${req.method} $path');
      Object? body = {'ok': true};
      if (path == '/api/search') {
        final q = req.url.queryParameters['q'];
        if (q == 'Мор') {
          await Future<void>.delayed(const Duration(milliseconds: 600)); // медленный старый запрос
          body = {
            'items': [
              {'type': 2, 'id': 5, 'title': 'Морозова Е. И.'},
            ],
            'ready': true,
          };
        } else if (q == 'Морозов') {
          body = {
            'items': [
              {'type': 2, 'id': 77, 'title': 'Морозов В. А.'},
            ],
            'ready': true,
          };
        } else {
          body = {'items': [], 'ready': false};
        }
      } else if (path == '/api/pins') {
        body = {'items': pins};
      } else if (path == '/api/target/2/77') {
        body = targetFixture(pinned: pins.isNotEmpty);
      } else if (path == '/api/pins/2/77' && req.method == 'PUT') {
        puts[path] = jsonDecode(req.body);
        pins = [
          {'type': 2, 'id': 77, 'title': 'Морозов В. А.'},
        ];
      } else if (path == '/api/pins/2/77' && req.method == 'DELETE') {
        pins = [];
      }
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    });
    final api = Api(client: client)..token = 'test-token';
    await t.pumpWidget(
      AppStyle(
        p: Palette.notebook,
        font: FontChoice.book,
        child: MaterialApp(home: SearchScreen(api: api)),
      ),
    );
    await settle(t);
    expect(find.text('Чьё расписание ищем?'), findsOneWidget);

    await t.enterText(find.byType(EditableText), 'Б-404');
    await settle(t);
    expect(find.text('Справочник ещё собирается'), findsOneWidget); // ready: false

    await t.enterText(find.byType(EditableText), 'Мор');
    await t.pump(const Duration(milliseconds: 300)); // ушёл запрос «Мор», ответ задерживается
    await t.enterText(find.byType(EditableText), 'Морозов');
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(find.text('Морозов В. А.'), findsOneWidget);
    await settle(t); // пришёл ответ на «Мор» — уже не нужен
    expect(find.text('Морозова Е. И.'), findsNothing);
    expect(find.text('Морозов В. А.'), findsOneWidget);

    await t.tap(find.text('Морозов В. А.'));
    await settle(t);
    await t.tap(find.byTooltip('Закрепить'));
    await settle(t);
    expect(puts['/api/pins/2/77'], {'title': 'Морозов В. А.'});
    await t.tap(find.byTooltip('Назад'));
    await settle(t);
    await t.tap(find.byTooltip('Очистить'));
    await settle(t);
    expect(find.text('Закреплённые'), findsOneWidget);
    expect(find.text('Морозов В. А.'), findsOneWidget); // закреплённый в недавних не повторяется

    await t.tap(find.text('Морозов В. А.'));
    await settle(t);
    await t.tap(find.byTooltip('Открепить'));
    await settle(t);
    expect(asked, contains('DELETE /api/pins/2/77'));
    await t.tap(find.byTooltip('Назад'));
    await settle(t);
    expect(find.text('Закреплённые'), findsNothing);
    expect(find.text('Недавние'), findsOneWidget);
    expect(find.text('Морозов В. А.'), findsOneWidget);
  });
}
