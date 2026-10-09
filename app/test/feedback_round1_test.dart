// Отзыв владельца о приложении (09.10): цель не сбрасывается при прокрутке,
// неделя листается свайпом и без «Сдать», плашки уведомлений видны в тёмной
// теме, файлы без повторов и с фильтром, «Новости и связь» — переход по кнопке,
// экраны сразу из запаса.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/api.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/screens/files.dart';
import 'package:uiboshki/screens/notify.dart';
import 'package:uiboshki/screens/study.dart';
import 'package:uiboshki/screens/week.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/capy_refresh.dart';
import 'package:uiboshki/widgets/common.dart';

import 'fake_api.dart';
import 'util.dart';

Widget _wrap(Widget child, {Palette p = Palette.depth}) => AppStyle(
  p: p,
  font: FontChoice.book,
  child: MaterialApp(home: child),
);

FileItem _f(int id, String title, String name, {String cat = 'lecture', bool text = false}) => FileItem.fromJson({
  'id': id,
  'title': title,
  'subject': 'ООП',
  'file_name': name,
  'category': cat,
  'has_text': text,
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('цель: выбор «4» остаётся после прокрутки вниз и обратно', (t) async {
    phone(t);
    final api = fakeApi();
    final course = Course.fromJson(Map<String, dynamic>.from(demoFixtures()['GET /api/sdo/grades/18673']));
    await t.pumpWidget(
      _wrap(
        CourseScreen(api: api, course: course),
        p: Palette.notebook,
      ),
    );
    await settle(t);
    await t.tap(find.bySemanticsLabel('Цель 4'));
    await settle(t);
    expect(find.text('ещё 12 баллов'), findsOneWidget);
    final list = find.byType(Scrollable).first;
    await t.drag(list, const Offset(0, -6000));
    await settle(t);
    expect(find.text('ещё 12 баллов'), findsNothing); // карточка ушла за экран
    await t.drag(list, const Offset(0, 6000));
    await settle(t);
    expect(find.text('ещё 12 баллов'), findsOneWidget);
  });

  testWidgets('неделя: свайп влево — следующая неделя; сроков сдачи в днях нет', (t) async {
    phone(t);
    final asked = <String>[];
    final api = fakeApi(requests: asked);
    await t.pumpWidget(
      _wrap(
        Scaffold(
          body: SafeArea(child: WeekScreen(api: api)),
        ),
      ),
    );
    await settle(t);
    expect(asked.where((r) => r.startsWith('GET /api/deadlines')), isEmpty);
    expect(find.textContaining('Сдать до'), findsNothing);
    final next = mondayOf(now()).add(const Duration(days: 7));
    await t.fling(find.text('Неделя'), const Offset(-400, 0), 1500);
    await settle(t);
    expect(asked, contains('GET /api/week?start=${iso(next)}'));
  });

  testWidgets('уведомления в тёмной теме: невыбранная плашка не белая', (t) async {
    phone(t);
    await t.pumpWidget(_wrap(NotifyScreen(api: fakeApi())));
    await settle(t);
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await settle(t);
    // было: невыбранные — белые (alpha: 1 у полупрозрачной line) и белый текст на них
    var off = 0;
    for (final label in ['выкл', '30 мин', '1 ч', '3 ч', 'своё']) {
      final pill = find.byKey(Key('remind:remind_first:$label'));
      if (pill.evaluate().isEmpty) continue;
      final c = t.widget<Material>(find.descendant(of: pill, matching: find.byType(Material)).first).color!;
      if (c == Palette.depth.accent) continue;
      off++;
      expect(c.a, lessThan(0.5), reason: label);
    }
    expect(off, greaterThan(0));
  });

  test('файлы: одинаковые названия — одной строкой, номера по порядку, лабы отдельно', () {
    final rows = groupSameTitle([
      _f(1, 'Лекция 10', 'l10.pdf'),
      _f(2, 'Лекция 2', 'l2.pptx'),
      _f(3, 'Лекция 2', 'l2.pdf', text: true),
      _f(4, 'Лекция 1', 'l1.pdf'),
    ]);
    expect([for (final r in rows) r.first.title], ['Лекция 1', 'Лекция 2', 'Лекция 10']);
    expect([for (final f in rows[1]) f.id], [3, 2]); // первым — файл с текстом
    expect(fileFilterOf(_f(5, 'Лабораторная работа 3', 'x.pdf', cat: 'practice')), 'lab');
    expect(fileFilterOf(_f(6, 'Практика 3', 'x.pdf', cat: 'practice')), 'practice');
  });

  testWidgets('файлы предмета: фильтр по типу оставляет только его', (t) async {
    phone(t);
    final files = [
      _f(1, 'Лекция 1', 'a.pdf'),
      _f(2, 'Практика 1', 'b.pdf', cat: 'practice'),
      _f(3, 'Лабораторная 1', 'c.pdf', cat: 'practice'),
    ];
    await t.pumpWidget(_wrap(SubjectFilesScreen(api: fakeApi(), subject: 'ООП', files: files)));
    await settle(t);
    expect(find.text('Лекция 1'), findsOneWidget);
    await t.ensureVisible(find.text('Лабы · 1'));
    await settle(t);
    await t.tap(find.text('Лабы · 1'));
    await settle(t);
    expect(find.text('Лекция 1'), findsNothing);
    expect(find.text('Лабораторная 1'), findsOneWidget);
  });

  testWidgets('экран открывается из запаса, без крутилки, пока идёт сеть', (t) async {
    SharedPreferences.setMockInitialValues({
      'uib_cache:/x': '{"at":"2026-10-09T09:00:00","body":"{\\"v\\":\\"старое\\"}"}',
    });
    final api = fakeApi(
      overrides: {
        'GET /api/x': {'v': 'новое'},
      },
    );
    await t.pumpWidget(
      _wrap(
        Scaffold(
          body: Loader<String>(
            load: () async => '${(await api.get('/x'))['v']}',
            builder: (context, v, _) => ListView(children: [Text(v)]),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    expect(find.byType(CapyLoading), findsNothing); // данные из запаса — без «загружаю»
    await settle(t);
    expect(find.text('новое'), findsOneWidget);
    expect(Api.base, isNotEmpty);
  });
}
