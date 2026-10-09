import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/screens/study.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/goal_card.dart';

import 'fake_api.dart';
import 'util.dart';

void main() {
  test('числа и отметки по-русски', () {
    expect(fmtNum(12), '12');
    expect(fmtNum(2.5), '2,5');
    expect(markWord('зачёт'), 'зачёт');
    expect(markWord('4'), '«4»');
    expect(dayMonth('2026-08-27'), '27 августа'); // Б6: подсказка у лекции, не «2026-08-27»
    expect(dayMonth(''), '');
  });

  testWidgets('предмет: цель, посещения, рост баллов; смена цели', (t) async {
    phone(t);
    final asked = <String>[];
    final api = fakeApi(requests: asked);
    final fx = demoFixtures();
    final course = Course.fromJson(Map<String, dynamic>.from(fx['GET /api/sdo/grades/18673']));
    await t.pumpWidget(
      AppStyle(
        p: Palette.notebook,
        font: FontChoice.book,
        child: MaterialApp(
          home: CourseScreen(api: api, course: course),
        ),
      ),
    );
    await settle(t);
    expect(find.text('Цель'), findsOneWidget);
    expect(find.text('впритык'), findsOneWidget);
    expect(find.text('по баллам уже набрано'), findsOneWidget); // цель по умолчанию — «3», 48 из 40
    expect(find.textContaining('пропущу лекцию 8 октября'), findsOneWidget);

    await t.tap(find.bySemanticsLabel('Цель 4'));
    await settle(t);
    expect(asked, contains('POST /api/sdo/goal/18673|4'));
    expect(find.text('ещё 12 баллов'), findsOneWidget);

    final list = find.byType(Scrollable).first;
    await t.scrollUntilVisible(find.textContaining('был на 3 из 6 прошедших'), 300, scrollable: list);
    await t.scrollUntilVisible(find.text('+8 за неделю'), 300, scrollable: list);
    await settle(t);
  });
}
