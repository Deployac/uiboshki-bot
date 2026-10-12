// «Сколько займёт работа» (Никита 12.10, вариант Б): у тестов СДО — их
// ограничение по времени («15 мин», «1 ч 30 мин») маленькой серой пометкой в
// «Сдать» и в листе по нажатию. У заданий и тестов без ограничения — ничего;
// в старом дизайне (features.design2 = false) — тоже ничего.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/screens/deadline_edit.dart';
import 'package:uiboshki/screens/deadlines.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

Widget _host(Widget child, {required bool design2}) => AppStyle(
  p: Palette.depth,
  font: FontChoice.book,
  design2: design2,
  child: MaterialApp(home: Scaffold(body: child)),
);

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Map<String, Object?> _item(int id, DateTime due, String subject, {int? limit, bool done = false, String? link}) => {
  'id': id,
  'subject': subject,
  'description': link ?? '',
  'due_date': iso(due),
  'due_time': _hm(due),
  'personal': false,
  'done': done ? 1 : 0,
  'can_edit': true,
  'edit_scope': 'me',
  'mine_changed': false,
  'can_submit': false,
  'reminders': [],
  'time_limit': limit,
};

final _at = DateTime(2026, 10, 9, 12, 12);
final _raw = [
  _item(1, DateTime(2026, 10, 9, 15, 50), 'Тест 1 · Анализ данных', limit: 15), // горит
  _item(2, DateTime(2026, 10, 15, 18), 'Тест 2 · Учетная деятельность', limit: 90),
  _item(3, DateTime(2026, 10, 16, 18), 'Тест 3 · Учетная деятельность'), // без ограничения
  _item(4, DateTime(2026, 10, 17, 23, 59), 'Практика 4 · Анализ данных'), // задание
  _item(5, DateTime(2026, 10, 5, 18), 'Тест 0 · Бизнес-анализ', limit: 20, done: true),
];

Future<void> _pumpList(WidgetTester t, {required bool design2, ValueChanged<Deadline>? onOpen}) async {
  t.view.physicalSize = const Size(1170, 5400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    _host(
      DeadlinesView(
        items: [for (final x in _raw) Deadline.fromJson(x)],
        extra: {for (final x in _raw) x['id'] as int: DlExtra.fromJson(x)},
        api: fakeApi(),
        at: _at,
        onToggle: (_, _) async {},
        onSubmit: (_) {},
        onOpen: onOpen ?? (_) {},
        onAdd: () {},
      ),
      design2: design2,
    ),
  );
  await settle(t);
}

void main() {
  test('подпись времени: минуты, часы, часы с минутами; без ограничения — ничего', () {
    expect(quizTimeText(15), '15 мин');
    expect(quizTimeText(60), '1 ч');
    expect(quizTimeText(90), '1 ч 30 мин');
    expect(quizTimeText(150), '2 ч 30 мин');
    expect(quizTimeText(null), isNull);
    expect(quizTimeText(0), isNull);
  });

  test('time_limit из /api/deadlines', () {
    expect(DlExtra.fromJson({'time_limit': 45}).timeLimit, 45);
    expect(DlExtra.fromJson({'time_limit': null}).timeLimit, isNull);
    expect(DlExtra.fromJson(const {}).timeLimit, isNull);
    expect(DlExtra.fromJson({'time_limit': 30}).hasChips(), isFalse); // без нового дизайна — не пометка
    expect(DlExtra.fromJson({'time_limit': 30}).hasChips(time: true), isTrue);
  });

  testWidgets('в новом дизайне — время у тестов с ограничением, у остальных ничего', (t) async {
    await _pumpList(t, design2: true);
    expect(find.text('15 мин'), findsOneWidget); // горящая карточка
    expect(find.text('1 ч 30 мин'), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz-time')), findsNWidgets(2));
    // пометка — под строкой предмета у своей работы
    final row = find.ancestor(of: find.text('Тест 2'), matching: find.byType(InkWell)).first;
    expect(find.descendant(of: row, matching: find.text('1 ч 30 мин')), findsOneWidget);
    for (final other in ['Тест 3', 'Практика 4']) {
      final r = find.ancestor(of: find.text(other), matching: find.byType(InkWell)).first;
      expect(
        find.descendant(of: r, matching: find.byKey(const ValueKey('quiz-time'))),
        findsNothing,
        reason: other,
      );
    }
    // серая, как «личный», а не цветная
    final chip = t.widget<Text>(find.text('1 ч 30 мин'));
    expect(chip.style?.color, Palette.depth.muted);

    // у сданного время не нужно
    await t.tap(find.text('Сдано · 1'));
    await settle(t);
    expect(find.text('Тест 0'), findsOneWidget);
    expect(find.text('20 мин'), findsNothing);
  });

  testWidgets('старый дизайн (откат design2) — без времени', (t) async {
    await _pumpList(t, design2: false);
    expect(find.byKey(const ValueKey('quiz-time')), findsNothing);
    expect(find.text('1 ч 30 мин'), findsNothing);
    expect(find.text('15 мин'), findsNothing);
  });

  for (final design2 in [true, false]) {
    testWidgets('лист действий теста: время ${design2 ? 'есть' : 'нет (старый дизайн)'}', (t) async {
      phone(t);
      final x = _raw[1];
      await t.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDeadlineActions(
                context,
                Deadline.fromJson(x),
                DlExtra.fromJson(x),
                due: 'чт, 15 октября · 18:00',
              ),
              child: const Text('открыть'),
            ),
          ),
          design2: design2,
        ),
      );
      await t.tap(find.text('открыть'));
      await settle(t);
      expect(find.text('Уже сдал'), findsOneWidget);
      expect(find.text('1 ч 30 мин'), design2 ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('тест из записи стенда (demo.json) — с временем в «Сдать»', (t) async {
    t.view.physicalSize = const Size(1170, 5400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(DeadlinesScreen(api: fakeApi()), design2: true));
    await settle(t);
    final row = find.ancestor(of: find.text('Тест 2'), matching: find.byType(InkWell)).first;
    expect(find.descendant(of: row, matching: find.text('30 мин')), findsOneWidget);
    final task = find.ancestor(of: find.text('Практика 2'), matching: find.byType(InkWell)).first;
    expect(find.descendant(of: task, matching: find.byKey(const ValueKey('quiz-time'))), findsNothing);
  });
}
