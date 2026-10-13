// «Тесты СДО» в уведомлениях (Никита 12.10): один пункт, по нажатию —
// несколько напоминаний до закрытия и «Тест открылся».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/screens/notify.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

Widget _wrap(Widget child) => AppStyle(
  p: Palette.depth,
  font: FontChoice.book,
  child: MaterialApp(home: child),
);

Future<void> _toQuiz(WidgetTester t) async {
  for (var i = 0; i < 6 && find.byKey(const Key('notify:quiz')).hitTestable().evaluate().isEmpty; i++) {
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await settle(t);
  }
}

void main() {
  testWidgets('раскрыть, выбрать два напоминания и выключить «открыли»', (t) async {
    phone(t);
    final bodies = <String, Object?>{};
    await t.pumpWidget(_wrap(NotifyScreen(api: fakeApi(bodies: bodies)))); // запись стенда — без новых ключей
    await settle(t);
    await _toQuiz(t);
    expect(find.text('Тесты СДО'), findsOneWidget);
    expect(find.text('когда откроют'), findsOneWidget); // по умолчанию: «открыли» — да, напоминаний нет
    expect(find.byKey(const Key('quiz:60')), findsNothing); // свёрнуто — плашек не видно

    await t.tap(find.byKey(const Key('notify:quiz')));
    await settle(t);
    await _toQuiz(t);
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await settle(t);
    expect(find.text('1 день'), findsOneWidget);
    await t.tap(find.byKey(const Key('quiz:10')));
    await settle(t);
    expect(bodies['POST /api/notify'], {
      'prefs': {
        'quiz_remind': [10],
      },
    });
    await t.tap(find.byKey(const Key('quiz:1440')));
    await settle(t);
    expect(bodies['POST /api/notify'], {
      'prefs': {
        'quiz_remind': [1440, 10],
      },
    });
    await t.tap(find.byKey(const Key('notify:quiz_open')));
    await settle(t);
    expect(bodies['POST /api/notify'], {
      'prefs': {'quiz_open': false},
    });
  });

  test('подпись пункта', () {
    expect(quizSummary([], true), 'когда откроют');
    expect(quizSummary([10, 1440, 60], false), 'за 1 день, 1 ч и 10 мин до закрытия');
    expect(quizSummary([180], true), 'за 3 ч до закрытия · когда откроют');
    expect(quizSummary([], false), 'выключено');
  });
}
