import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uiboshki/api/api.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/screens/deadline_edit.dart';
import 'package:uiboshki/screens/deadlines.dart';
import 'package:uiboshki/screens/homework.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/common.dart';

import 'fake_api.dart';
import 'util.dart';

/// Ответ с ошибкой сервера (400 и текст detail).
class Fail {
  final String detail;
  const Fail(this.detail);
}

/// Api на ответах стенда, который записывает и тело любого запроса
/// (fakeApi помнит тела только у POST).
Api recApi(List<(String, Object?)> log, Map<String, Object?> overrides) {
  final fx = demoFixtures();
  return Api(
    client: MockClient((req) async {
      final path = req.url.path.replaceFirst('/api/v1/', '/api/');
      final key = '${req.method} $path${req.url.query.isEmpty ? '' : '?${req.url.query}'}';
      log.add((key, req.body.isEmpty ? null : jsonDecode(req.body)));
      final body = overrides.containsKey(key) ? overrides[key] : (fx[key] ?? {'ok': true});
      if (body is Fail) return http.Response.bytes(utf8.encode(jsonEncode({'detail': body.detail})), 400);
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    }),
  )..token = 't';
}

Widget host(Widget child) => AppStyle(
  p: Palette.notebook,
  font: FontChoice.book,
  child: MaterialApp(home: Scaffold(body: child)),
);

/// Общий срок через три дня: поменять можно только у себя, одно напоминание.
Map<String, Object?> sharedItem({bool mineChanged = false}) {
  final d = now().add(const Duration(days: 3));
  return {
    'id': 9,
    'subject': 'Практика 4 · Анализ данных',
    'description': 'https://online-edu.mirea.ru/mod/assign/view.php?id=5011',
    'due_date': iso(d),
    'due_time': '23:59',
    'personal': false,
    'done': 0,
    'can_edit': true,
    'edit_scope': 'me',
    'mine_changed': mineChanged,
    'can_submit': false,
    'reminders': [],
  };
}

const list = 'GET /api/deadlines?include_done=true';

void main() {
  test('быстрые даты: понедельник не совпадает с «Завтра» и «Через неделю»', () {
    final thu = quickDates(DateTime(2026, 10, 8));
    expect([for (final q in thu) q.label], ['Сегодня', 'Завтра', 'Пн, 12 окт', 'Через неделю']);
    expect(thu[3].date, DateTime(2026, 10, 15));
    // воскресенье: понедельник = «Завтра» → ближайшая пятница
    expect(quickDates(DateTime(2026, 10, 11))[2].label, 'Пт, 16 окт');
    // понедельник: следующий понедельник = «Через неделю» → пятница
    expect(quickDates(DateTime(2026, 10, 12))[2].label, 'Пт, 16 окт');
  });

  testWidgets('свой срок: «+» → название, «Завтра» → POST /api/deadlines', (t) async {
    phone(t);
    final log = <(String, Object?)>[];
    await t.pumpWidget(host(DeadlinesScreen(api: recApi(log, {}))));
    await settle(t);
    await t.tap(find.byTooltip('Свой срок'));
    await settle(t);
    expect(find.text('Новый срок'), findsOneWidget);
    expect(find.textContaining('Личный — видишь только ты'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Распечатать отчёт');
    await t.tap(find.text('Завтра'));
    await t.enterText(find.byType(TextField).last, 'в копицентре у А-корпуса');
    await t.tap(find.text('Добавить'));
    await settle(t);
    final sent = log.firstWhere((r) => r.$1 == 'POST /api/deadlines').$2 as Map;
    final tomorrow = now().add(const Duration(days: 1));
    expect(sent, {
      'subject': 'Распечатать отчёт',
      'due_date': iso(tomorrow),
      'due_time': '23:59',
      'description': 'в копицентре у А-корпуса',
    });
    expect(find.text('Срок добавлен — видишь только ты'), findsOneWidget);
    expect(log.where((r) => r.$1 == list).length, 2); // список перечитан
  });

  testWidgets('общий срок: «Изменить» — только у тебя, PATCH; «Как у всех»', (t) async {
    phone(t);
    final log = <(String, Object?)>[];
    final api = recApi(log, {
      list: {
        'items': [sharedItem(mineChanged: true)],
      },
      'PATCH /api/deadlines/9': {'ok': true, 'id': 9, 'scope': 'me'},
    });
    await t.pumpWidget(host(DeadlinesScreen(api: api)));
    await settle(t);
    expect(find.text('изменён у тебя'), findsOneWidget); // чип на карточке
    await t.tap(find.text('Практика 4')); // работа строкой, предмет — под ней
    await settle(t);
    expect(find.text('Убрать у себя'), findsOneWidget);
    expect(find.text('Как у всех'), findsOneWidget);
    expect(find.text('Задание в СДО'), findsOneWidget);
    await t.tap(find.text('Изменить'));
    await settle(t);
    expect(find.textContaining('Изменится только у тебя'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Практика 4 · сдаю позже');
    await t.tap(find.text('Сохранить'));
    await settle(t);
    final sent = log.firstWhere((r) => r.$1 == 'PATCH /api/deadlines/9').$2 as Map;
    expect(sent['subject'], 'Практика 4 · сдаю позже');
    expect(sent['due_date'], iso(now().add(const Duration(days: 3))));
    expect(find.text('Сохранено у тебя'), findsOneWidget);

    await t.tap(find.text('Практика 4'));
    await settle(t);
    await t.tap(find.text('Как у всех'));
    await settle(t);
    expect(log.map((r) => r.$1), contains('DELETE /api/deadlines/9/mine'));
  });

  testWidgets('убрать у себя — после «точно?»', (t) async {
    phone(t);
    final log = <(String, Object?)>[];
    final api = recApi(log, {
      list: {
        'items': [sharedItem()],
      },
    });
    await t.pumpWidget(host(DeadlinesScreen(api: api)));
    await settle(t);
    await t.tap(find.text('Практика 4'));
    await settle(t);
    await t.tap(find.text('Убрать у себя'));
    await settle(t);
    expect(find.text('У группы этот срок останется.'), findsOneWidget);
    await t.tap(find.text('Убрать'));
    await settle(t);
    expect(log.map((r) => r.$1), contains('DELETE /api/deadlines/9'));
  });

  testWidgets('напоминание: «за 3 часа» → в списке, крестик убирает', (t) async {
    phone(t);
    final log = <(String, Object?)>[];
    final api = recApi(log, {
      list: {
        'items': [sharedItem()],
      },
      'POST /api/deadlines/9/remind': {'ok': true, 'at': '2026-10-11 20:59', 'label': '11 октября в 20:59'},
    });
    await t.pumpWidget(host(DeadlinesScreen(api: api)));
    await settle(t);
    await t.tap(find.text('Практика 4'));
    await settle(t);
    await t.tap(find.text('Напомнить'));
    await settle(t);
    await t.tap(find.text('за 3 часа'));
    await settle(t);
    expect(log.firstWhere((r) => r.$1 == 'POST /api/deadlines/9/remind').$2, {'preset': '3h'});
    expect(find.text('11 октября в 20:59'), findsOneWidget);
    await t.tap(find.byTooltip('Убрать напоминание'));
    await settle(t);
    expect(log.map((r) => r.$1), contains('DELETE /api/deadlines/9/remind?at=2026-10-11+20%3A59'));
    expect(find.text('11 октября в 20:59'), findsNothing);
  });

  testWidgets('напоминание: ошибка сервера — текстом в листе', (t) async {
    phone(t);
    final api = recApi([], {
      list: {
        'items': [sharedItem()],
      },
      'POST /api/deadlines/9/remind': const Fail('это время уже прошло'),
    });
    await t.pumpWidget(host(DeadlinesScreen(api: api)));
    await settle(t);
    await t.tap(find.text('Практика 4'));
    await settle(t);
    await t.tap(find.text('Напомнить'));
    await settle(t);
    await t.tap(find.text('за час'));
    await settle(t);
    expect(find.text('это время уже прошло'), findsOneWidget);
  });

  testWidgets('ДЗ группы по стенду: к паре, «Прислать файл» без Telegram — текст ошибки', (t) async {
    phone(t);
    final log = <(String, Object?)>[];
    final api = recApi(log, {'POST /api/homework/2/send': const Fail('Аккаунт без Telegram — файл прислать некуда')});
    await t.pumpWidget(host(HomeworkScreen(api: api)));
    await settle(t);
    expect(find.text('ДЗ группы'), findsOneWidget);
    expect(find.text('3 задания от старосты'), findsNothing); // без курсивной подписи (2.4)
    expect(find.text('Задачи 4–9 из методички, стр. 41'), findsOneWidget);
    expect(find.text('к паре · пн, 5 окт'), findsOneWidget); // один формат дат (2.14)
    expect(find.text('Прислать файл'), findsOneWidget); // файл только у одного
    await t.tap(find.text('Прислать файл'));
    await settle(t);
    expect(log.map((r) => r.$1), contains('POST /api/homework/2/send'));
    expect(find.text('Аккаунт без Telegram — файл прислать некуда'), findsOneWidget);
  });

  testWidgets('ДЗ группы: прошедшие — ниже, под «Прошло», и бледнее', (t) async {
    phone(t);
    final day = now();
    Map<String, Object?> hw(int id, String subject, int shift) => {
      'id': id,
      'subject': subject,
      'content': '',
      'lesson_date': shift == 99 ? '' : iso(day.add(Duration(days: shift))),
      'has_file': false,
    };
    final api = recApi([], {
      'GET /api/homework': {
        'items': [hw(1, 'Было вчера', -1), hw(2, 'Сегодня', 0), hw(3, 'Без даты', 99), hw(4, 'Завтра', 1)],
      },
    });
    await t.pumpWidget(host(HomeworkScreen(api: api)));
    await settle(t);
    double y(String text) => t.getTopLeft(find.text(text)).dy;
    expect(find.text('Прошло'), findsOneWidget);
    for (final x in ['Сегодня', 'Без даты', 'Завтра']) {
      expect(y(x), lessThan(y('Прошло')));
    }
    expect(y('Было вчера'), greaterThan(y('Прошло')));
    final faded = t.widget<Opacity>(find.ancestor(of: find.text('Было вчера'), matching: find.byType(Opacity)).first);
    expect(faded.opacity, lessThan(1));
    expect(find.text('к паре · ${shortDay(iso(day))}'), findsOneWidget);
    expect(shortDay('2026-10-09'), 'пт, 9 окт');
  });

  testWidgets('заметки: сегодня и завтра', (t) async {
    phone(t);
    final log = <(String, Object?)>[];
    final today = iso(now());
    final api = recApi(log, {
      'GET /api/notes?date=$today': {
        'date': today,
        'items': [
          {'subject': 'Матан', 'text': 'контрольная в 401'},
        ],
      },
    });
    await t.pumpWidget(host(NotesScreen(api: api)));
    await settle(t);
    expect(log.map((r) => r.$1), contains('GET /api/notes?date=$today'));
    expect(find.text('Матан'), findsOneWidget);
    expect(find.text('контрольная в 401'), findsOneWidget);
    expect(find.textContaining('Сегодня ·'), findsOneWidget);
    expect(find.textContaining('Завтра ·'), findsNothing); // на завтра пусто
  });

  testWidgets('вкладка «Сдать»: плитки ДЗ и заметок ведут на свои экраны', (t) async {
    phone(t);
    final api = fakeApi();
    await t.pumpWidget(host(DeadlinesScreen(api: api)));
    await settle(t);
    await t.tap(find.text('ДЗ группы'));
    await settle(t);
    expect(find.text('Доделать лабу 2: класс «Счёт» с наследованием'), findsOneWidget);
  });
}
