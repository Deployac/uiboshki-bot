// «Сдать» по варианту 24А (владелец, 09.10): без строки «1 горит · 27
// впереди · 4 сдано» над заголовком — переключатель «Впереди · N | Сдано · N»;
// горящее — большой карточкой сверху, остальное — по неделям с датой слева
// (сегодня — красным, завтра — жёлтым), сданное — отдельно, свежее сверху.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/screens/deadline_edit.dart';
import 'package:uiboshki/screens/deadlines.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/common.dart';

import 'fake_api.dart';
import 'util.dart';

const list = 'GET /api/deadlines?include_done=true';

Widget host(Widget child) => AppStyle(
  p: Palette.depth,
  font: FontChoice.book,
  child: MaterialApp(home: Scaffold(body: child)),
);

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Map<String, Object?> item(int id, DateTime due, String subject, {bool done = false, bool submit = false}) => {
  'id': id,
  'subject': subject,
  'description': '',
  'due_date': iso(due),
  'due_time': _hm(due),
  'personal': false,
  'done': done ? 1 : 0,
  'can_edit': true,
  'edit_scope': 'me',
  'mine_changed': false,
  'can_submit': submit,
  'reminders': [],
};

/// Высокий экран: все группы строятся сразу, без прокрутки.
void tall(WidgetTester t) {
  t.view.physicalSize = const Size(1170, 5400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

double top(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

Color? colorOf(WidgetTester t, String text) => t.widget<Text>(find.text(text)).style?.color;

void main() {
  test('название срока: работа отдельно, предмет без «(Экз)»', () {
    expect(splitTitle('Практика 5-6 · Анализ данных (Экз)'), (task: 'Практика 5-6', course: 'Анализ данных'));
    expect(splitTitle('Тест 2 · Учетная деятельность (Зач)'), (task: 'Тест 2', course: 'Учетная деятельность'));
    expect(splitTitle('Распечатать отчёт'), (task: 'Распечатать отчёт', course: ''));
  });

  test('подписи недель: эта, следующая, дальше — даты', () {
    final fri = DateTime(2026, 10, 9, 12, 12);
    expect(weekLabel(DateTime(2026, 10, 5), fri), 'Эта неделя');
    expect(weekLabel(DateTime(2026, 10, 12), fri), 'Следующая');
    expect(weekLabel(DateTime(2026, 10, 19), fri), '19–25 октября');
    expect(weekLabel(DateTime(2026, 10, 26), fri), '26 октября – 1 ноября');
  });

  test('горит — меньше суток до срока', () {
    final at = DateTime(2026, 10, 9, 12, 12);
    Deadline d(String date, String time) => Deadline(id: 1, subject: 'x', dueDate: date, dueTime: time);
    expect(isBurning(d('2026-10-09', '15:50'), at), isTrue);
    expect(isBurning(d('2026-10-10', '10:00'), at), isTrue); // завтра утром — тоже меньше суток
    expect(isBurning(d('2026-10-10', '18:00'), at), isFalse);
    expect(isBurning(d('2026-10-09', '10:00'), at), isFalse); // прошёл
  });

  testWidgets('по API: переключатель с числами, горящее сверху, «Сдать» открывает лист', (t) async {
    phone(t);
    final n = now();
    final asked = <String>[];
    final api = fakeApi(
      requests: asked,
      overrides: {
        list: {
          'items': [
            item(1, n.add(const Duration(hours: 2, minutes: 30)), 'Практика 5-6 · Анализ данных (Экз)', submit: true),
            item(2, n.add(const Duration(days: 3)), 'Практика 1 · Учетная деятельность'),
            item(3, n.add(const Duration(days: 10)), 'Кейс 1 · Анализ данных'),
            item(4, n.add(const Duration(days: 20)), 'Курсовая: глава 1 · Бизнес-анализ'),
            item(5, n.subtract(const Duration(days: 3)), 'Эссе · Бизнес-анализ', done: true),
            item(6, n.subtract(const Duration(days: 9)), 'Тест 1 · Анализ данных', done: true),
            item(7, n.subtract(const Duration(days: 1)), 'Тест 2 · Учетная деятельность (Зач)'),
          ],
        },
      },
    );
    await t.pumpWidget(host(DeadlinesScreen(api: api)));
    await settle(t);

    // над заголовком — ни строки с числами; числа — на переключателе
    expect(find.textContaining(RegExp(r'\d+ (горит|впереди|сдано)')), findsNothing);
    expect(find.text('Впереди · 4'), findsOneWidget); // просроченный — не «впереди»
    expect(find.text('Сдано · 2'), findsOneWidget);

    // горящее — большой карточкой выше недель, предмет строкой под работой
    final hot = find.ancestor(of: find.textContaining('горит ·'), matching: find.byType(Tile)).first;
    expect(find.descendant(of: hot, matching: find.text('Практика 5-6')), findsOneWidget);
    expect(find.descendant(of: hot, matching: find.textContaining('Анализ данных')), findsOneWidget);
    expect(find.descendant(of: hot, matching: find.text('ч')), findsOneWidget);
    expect(top(t, hot), lessThan(top(t, find.byType(Section).first)));
    expect(find.text('Практика 5-6'), findsOneWidget); // в неделях не повторяется

    // недели — по порядку, просроченное — в конце
    String label(int days) => weekLabel(mondayOfDay(n.add(Duration(days: days))), n);
    final labels = <String>{label(3), label(10), label(20)}.toList();
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.text('Срок прошёл · 1'), findsOneWidget);
    expect(top(t, find.text(labels.first)), lessThan(top(t, find.text(labels.last))));
    expect(top(t, find.text(labels.last)), lessThan(top(t, find.text('Срок прошёл · 1'))));

    await t.tap(find.descendant(of: hot, matching: find.text('Сдать')));
    await settle(t);
    expect(asked, contains('GET /api/sdo/submit-rules?cmid=0&deadline_id=1'));
  });

  testWidgets('«Сдано»: только сданное, свежее сверху; и обратно', (t) async {
    phone(t);
    final n = now();
    final api = fakeApi(
      overrides: {
        list: {
          'items': [
            item(2, n.add(const Duration(days: 3)), 'Практика 1 · Учетная деятельность'),
            item(6, n.subtract(const Duration(days: 9)), 'Тест 1 · Анализ данных', done: true),
            item(5, n.subtract(const Duration(days: 3)), 'Эссе · Бизнес-анализ', done: true),
          ],
        },
      },
    );
    await t.pumpWidget(host(DeadlinesScreen(api: api)));
    await settle(t);
    expect(find.text('Эссе'), findsNothing);
    expect(find.textContaining('горит ·'), findsNothing); // через три дня — не горит

    await t.tap(find.text('Сдано · 2'));
    await settle(t);
    expect(find.text('Практика 1'), findsNothing);
    expect(top(t, find.text('Эссе')), lessThan(top(t, find.text('Тест 1'))));
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));

    await t.tap(find.text('Впереди · 1'));
    await settle(t);
    expect(find.text('Практика 1'), findsOneWidget);
    expect(find.text('Эссе'), findsNothing);
  });

  testWidgets('пусто: «Всё сдано» с капибарой, в «Сдано» — подсказка', (t) async {
    phone(t);
    final api = fakeApi(
      overrides: {
        list: {'items': []},
      },
    );
    await t.pumpWidget(host(DeadlinesScreen(api: api)));
    await settle(t);
    expect(find.text('Впереди · 0'), findsOneWidget);
    expect(find.text('Всё сдано'), findsOneWidget);
    await t.tap(find.text('Сдано · 0'));
    await settle(t);
    expect(find.text('Пока ничего'), findsOneWidget);
  });

  testWidgets('макет 24А на пятницу 9 октября, 12:12: отсчёт, недели, цвет даты', (t) async {
    tall(t);
    final at = DateTime(2026, 10, 9, 12, 12);
    final raw = [
      item(1, DateTime(2026, 10, 9, 15, 50), 'Практика 5-6 · Анализ данных (Экз)', submit: true),
      item(2, DateTime(2026, 10, 9, 23, 59), 'Отчёт · Учетная деятельность'),
      item(3, DateTime(2026, 10, 10, 18), 'Практика 1 · Учетная деятельность (Зач)'),
      item(4, DateTime(2026, 10, 15, 12, 30), 'Кейс 1 · Анализ данных'),
      item(5, DateTime(2026, 10, 22, 12, 30), 'Тест 3 · Анализ данных'),
      item(6, DateTime(2026, 11, 1, 23, 59), 'Эссе · Бизнес-анализ'),
      item(7, DateTime(2026, 10, 5, 16), 'Тест 2 · Учетная деятельность'),
      item(8, DateTime(2026, 10, 2, 18), 'Практика 2 · Анализ данных', done: true),
      item(9, DateTime(2026, 10, 7, 18), 'Лабораторная 3 · ООАиП', done: true),
    ];
    final submitted = <int>[], toggled = <(int, bool)>[];
    await t.pumpWidget(
      host(
        DeadlinesView(
          items: [for (final x in raw) Deadline.fromJson(x)],
          extra: {for (final x in raw) x['id'] as int: DlExtra.fromJson(x)},
          api: fakeApi(),
          at: at,
          onToggle: (d, done) async => toggled.add((d.id, done)),
          onSubmit: (d) => submitted.add(d.id),
          onOpen: (_) {},
          onAdd: () {},
        ),
      ),
    );
    await settle(t);
    final p = Palette.depth;

    expect(find.text('Впереди · 6'), findsOneWidget);
    expect(find.text('Сдано · 2'), findsOneWidget);
    // горит: «до 15:50», 3 ч 38, кнопка «Сдать»
    expect(find.text('горит · до 15:50'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(colorOf(t, '38'), p.danger);
    // 2.16: «3 ч 38 мин», а не «3 ч 38»
    final hot = find.ancestor(of: find.text('горит · до 15:50'), matching: find.byType(Tile)).first;
    expect(find.descendant(of: hot, matching: find.text('ч')), findsOneWidget);
    expect(find.descendant(of: hot, matching: find.text('мин')), findsOneWidget);

    // недели по порядку под горящим
    final order = ['Эта неделя', 'Следующая', '19–25 октября', '26 октября – 1 ноября', 'Срок прошёл · 1'];
    var y = top(t, find.textContaining('горит ·'));
    for (final l in order) {
      final next = top(t, find.text(l));
      expect(next, greaterThan(y), reason: l);
      y = next;
    }

    // дата слева: сегодня — красным, завтра — жёлтым, дальше — обычным,
    // просроченное — серым и с месяцем
    expect(colorOf(t, '9'), p.danger);
    expect(colorOf(t, '10'), p.warn);
    expect(colorOf(t, '15'), p.text);
    expect(colorOf(t, '5'), p.muted);
    expect(find.text('сб'), findsOneWidget);
    expect(find.text('окт'), findsOneWidget);

    // предмет — с точкой цвета и временем, вид контроля не повторяем
    expect(find.textContaining('Учетная деятельность · 18:00'), findsOneWidget);
    expect(find.textContaining('(Зач)'), findsNothing);

    await t.tap(find.descendant(of: find.byWidgetPredicate((w) => w is FilledButton), matching: find.text('Сдать')));
    expect(submitted, [1]);

    // свайп вправо по строке — «сдал»
    await t.drag(find.text('Практика 1'), const Offset(500, 0));
    await settle(t);
    expect(toggled, [(3, true)]);

    await t.tap(find.text('Сдано · 2'));
    await settle(t);
    expect(top(t, find.text('Лабораторная 3')), lessThan(top(t, find.text('Практика 2'))));
    expect(find.textContaining('горит ·'), findsNothing);
  });
}

DateTime mondayOfDay(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
