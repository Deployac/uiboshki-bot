// Тексты и вид (проверка 09.10, план PR 3): длинные названия мельче и без
// разрыва «финансово-» (2.3), одинаковые пустые дни в обоих видах недели
// (2.13), «Вопросы к зачёту» у зачётного предмета (2.15), «Сейчас: группа»
// и «Я староста» в «Ещё → Группа» (2.7), «ДЗ группы» одной строкой на
// маленьком экране (2.17).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/screens/deadlines.dart';
import 'package:uiboshki/screens/files.dart';
import 'package:uiboshki/screens/group_pick.dart';
import 'package:uiboshki/screens/lesson.dart';
import 'package:uiboshki/screens/week.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/common.dart';

import 'fake_api.dart';
import 'util.dart';

const _long = 'Анализ и диагностика финансово-хозяйственной деятельности предприятия';

Widget _wrap(Widget child) => AppStyle(
  p: Palette.depth,
  font: FontChoice.book,
  child: MaterialApp(home: Scaffold(body: child)),
);

/// Маленький телефон с крупным системным шрифтом — как в layout_test.
void _small(WidgetTester t) {
  t.view.devicePixelRatio = 2;
  t.view.physicalSize = const Size(640, 1136);
  t.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

FileItem _file(int id, String title, String cat, String subject) => FileItem.fromJson({
  'id': id,
  'title': title,
  'subject': subject,
  'file_name': '$id.pdf',
  'category': cat,
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  testWidgets('длинное название пары — мельче, до трёх строк, «финансово-» не отрывается', (t) async {
    _small(t);
    await loadFonts();
    const lesson = Lesson(
      start: '10:40',
      end: '12:10',
      title: _long,
      kind: 'лекция',
      room: 'ИВЦ-126 (В-78)',
      teacher: 'Зорина Н. В.',
      status: '',
    );
    await t.pumpWidget(_wrap(LessonScreen(api: fakeApi(), lesson: lesson)));
    await settle(t);
    final title = find.textContaining('диагностика');
    final text = t.widget<Text>(title);
    expect(text.maxLines, 3);
    expect(text.style!.fontSize, lessThan(30));
    expect(text.data, contains('финансово-⁠хозяйственной')); // перенос только целым словом
    final para = t.renderObject<RenderParagraph>(find.descendant(of: title, matching: find.byType(RichText)));
    expect(para.didExceedMaxLines, isFalse);
    // вид пары — строкой под названием, не курсивом сверху (2.4)
    expect(find.text('Лекция'), findsOneWidget);
    expect(t.getTopLeft(find.text('Лекция')).dy, greaterThan(t.getTopLeft(title).dy));
    expect(titleSize('Неделя', 34), 34);
    expect(titleSize(_long, 34), lessThan(titleSize('Анализ данных и машинное обучение', 34)));
  });

  testWidgets('неделя: пустой день одинаково лентой и по дням, день недели с заглавной', (t) async {
    phone(t);
    final monday = mondayOf(now());
    final api = fakeApi(
      overrides: {
        'GET /api/week?start=${iso(monday)}': {'week': 6, 'days': []},
        for (var i = 0; i < 7; i++) 'GET /api/day?date=${iso(monday.add(Duration(days: i)))}': {'lessons': []},
      },
    );
    await t.pumpWidget(_wrap(WeekScreen(api: api)));
    await settle(t);
    final head = dayHead(now(), today: true);
    expect(head[0], head[0].toUpperCase());
    expect(find.text(head), findsOneWidget);
    expect(find.text(noLessonsTitle), findsWidgets);
    expect(find.text(noLessonsText), findsWidgets);
    expect(find.text('отдыхай'), findsNothing);
    expect(find.text('Сегодня пар нет'), findsNothing);

    await t.tap(find.byTooltip('По дням'));
    await settle(t);
    expect(find.text(head), findsOneWidget);
    expect(find.text(noLessonsTitle), findsOneWidget);
    expect(find.text(noLessonsText), findsOneWidget);
  });

  testWidgets('файлы зачётного предмета: «Вопросы к зачёту», у экзамена — «Экзамен»', (t) async {
    phone(t);
    // в журнале стенда «Основы бизнес-анализа» — зачёт, «Анализ данных» — экзамен
    for (final (subject, label) in [
      ('Основы бизнес-анализа в ИТ-сфере', 'Вопросы к зачёту'),
      ('Анализ данных', 'Экзамен'),
    ]) {
      final files = [_file(1, 'Лекция 1', 'lecture', subject), _file(2, 'Вопросы', 'exam', subject)];
      await t.pumpWidget(_wrap(SubjectFilesScreen(key: UniqueKey(), api: fakeApi(), subject: subject, files: files)));
      await settle(t);
      expect(find.text('$label · 1'), findsOneWidget, reason: subject);
      expect(find.text(label), findsOneWidget, reason: subject); // и заголовок раздела
    }
    expect(isCreditCourse({'courses': []}, 'Анализ данных'), isNull);
    expect(
      isCreditCourse({
        'courses': [
          {
            'title': 'Физкультура',
            'marks': [
              {'at': 40, 'label': 'зачёт'},
            ],
          },
        ],
      }, 'Физкультура'),
      isTrue,
    );
  });

  testWidgets('«Ещё → Группа»: «Сейчас: …» сверху, «Я староста» — запрос владельцу', (t) async {
    phone(t);
    await t.pumpWidget(_wrap(GroupPickScreen(api: fakeApi())));
    await settle(t);
    expect(find.text('Сейчас: УИБО-03-24'), findsOneWidget);
    expect(find.text('Я староста этой группы'), findsNothing); // своя группа — у неё староста бота

    final asked = <String>[];
    final api = fakeApi(
      requests: asked,
      overrides: {
        'GET /api/me': {
          'id': 222,
          'group': {'id': 5001, 'name': 'УИБО-01-24', 'own': false},
        },
      },
    );
    await t.pumpWidget(_wrap(GroupPickScreen(key: UniqueKey(), api: api)));
    await settle(t);
    expect(find.text('Сейчас: УИБО-01-24'), findsOneWidget);
    final current = t.getTopLeft(find.text('Сейчас: УИБО-01-24')).dy;
    expect(current, lessThan(t.getTopLeft(find.byType(TextField)).dy));
    expect(t.getTopLeft(find.text('Я староста этой группы')).dy, greaterThan(t.getTopLeft(find.byType(TextField)).dy));
    await t.tap(find.text('Я староста этой группы'));
    await settle(t);
    expect(asked, contains('POST /api/me/group/admin'));
    expect(find.text('Запрос отправлен — ответ придёт в бота.'), findsOneWidget);

    // первый выбор — как раньше, без «Сейчас»
    await t.pumpWidget(_wrap(GroupPickScreen(key: UniqueKey(), api: api, required: true)));
    await settle(t);
    expect(find.textContaining('Сейчас:'), findsNothing);
  });

  testWidgets('маленький экран: «ДЗ группы» одной строкой', (t) async {
    _small(t);
    await loadFonts();
    await t.pumpWidget(_wrap(DeadlinesScreen(api: fakeApi())));
    await settle(t);
    final para = t.renderObject<RenderParagraph>(
      find.descendant(of: find.text('ДЗ группы'), matching: find.byType(RichText)),
    );
    expect(para.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 9)).length, 1);
    expect(para.size.height, lessThan(15 * 1.3 * 1.3 * 1.5)); // одна строка
  });
}
