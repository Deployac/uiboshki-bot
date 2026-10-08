import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/screens/lesson.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

void main() {
  test('один и тот же предмет в журнале и в файлах', () {
    expect(sameSubject('Анализ данных', 'анализ данных'), isTrue);
    expect(sameSubject('Учетная деятельность на предприятии', 'Учётная деятельность на предприятии'), isTrue);
    expect(sameSubject('Анализ данных', 'Архитектура предприятия'), isFalse);
  });

  testWidgets('пара: где, кто, поток, баллы и лекции; все пары преподавателя', (t) async {
    phone(t);
    final asked = <String>[];
    final api = fakeApi(
      requests: asked,
      overrides: {
        'GET /api/search?q=%D0%A1%D0%B8%D0%B3%D0%B0%D0%BD%D1%8C%D0%BA%D0%BE%D0%B2+%D0%90.+%D0%90.&type=2': {
          'items': [
            {'type': 2, 'id': 77, 'title': 'Сиганьков А. А.'},
          ],
        },
        'GET /api/target/2/77': {
          'title': 'Сиганьков А. А.',
          'weeks': [
            {
              'days': [
                {
                  'date': '2099-01-05',
                  'lessons': [
                    {
                      'start': '09:00',
                      'end': '10:30',
                      'title': 'Моделирование бизнес-процессов',
                      'kind': 'лекция',
                      'room': 'А-17 (В-78)',
                      'groups': 'УИБО-01-24, УИБО-02-24',
                    },
                  ],
                },
              ],
            },
          ],
        },
      },
    );
    const lesson = Lesson(
      start: '09:00',
      end: '10:30',
      title: 'Моделирование бизнес-процессов',
      kind: 'лекция',
      room: 'А-17 (В-78)',
      teacher: 'Сиганьков А. А.',
      status: '',
      groups: 'УИБО-01-24, УИБО-02-24, УИБО-03-24',
    );
    await t.pumpWidget(
      AppStyle(
        p: Palette.depth,
        font: FontChoice.strict,
        child: MaterialApp(
          home: LessonScreen(api: api, lesson: lesson),
        ),
      ),
    );
    await settle(t);
    expect(find.text('А-17'), findsOneWidget);
    expect(find.text('корпус В-78 · расписание аудитории'), findsOneWidget);
    expect(find.text('Поток · 3 группы'), findsOneWidget);
    expect(find.text('Баллы БРС'), findsOneWidget); // предмет нашёлся в журнале
    expect(find.text('до «5» ещё 16'), findsOneWidget);

    await t.tap(find.text('Сиганьков А. А.'));
    await settle(t);
    expect(asked.any((k) => k.startsWith('GET /api/target/2/77')), isTrue);
    expect(find.text('преподаватель'), findsOneWidget);
    expect(find.textContaining('УИБО-01-24, УИБО-02-24'), findsOneWidget); // чьи это пары
  });
}
