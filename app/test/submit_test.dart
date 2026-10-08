import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/screens/submit.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

void main() {
  test('правила задания: типы, число файлов, размер', () {
    final r = SubmitRules.fromJson({
      'accepted': ['.ZIP'],
      'labels': ['Архив ZIP'],
      'maxfiles': 5,
      'maxbytes': 10485760,
    });
    expect(r.fits('отчёт.zip'), isTrue);
    expect(r.fits('отчёт.docx'), isFalse);
    expect(r.perSubmit, 3); // за раз — не больше трёх
    expect(r.describe(), 'Архив ZIP · до 3 файлов · до 10 МБ');
    expect(SubmitRules.fromJson({'maxfiles': 1}).describe(), 'любые файлы · до 1 файла');
    expect(SubmitRules.fromJson({'closed': 'срок вышел'}).closed, 'срок вышел');
  });

  testWidgets('сдать файлом: чужой тип отсекается, zip уходит, «Сдано»', (t) async {
    phone(t);
    final asked = <String>[];
    final bodies = <String, Object?>{};
    final api = fakeApi(requests: asked, bodies: bodies);
    Future<List<Picked>> pick(List<String> accepted) async {
      expect(accepted, ['.zip']); // системное окно — сразу с фильтром задания
      return [
        (name: 'отчёт.docx', bytes: Uint8List.fromList([1, 2])),
        (name: 'отчёт.zip', bytes: Uint8List.fromList([3, 4, 5])),
      ];
    }

    await t.pumpWidget(
      AppStyle(
        p: Palette.depth,
        font: FontChoice.book,
        child: MaterialApp(
          home: Scaffold(
            body: SubmitSheet(api: api, title: 'Практика 3', deadlineId: 7, pick: pick),
          ),
        ),
      ),
    );
    await settle(t);
    expect(asked, contains('GET /api/sdo/submit-rules?cmid=0&deadline_id=7'));
    expect(find.textContaining('Архив ZIP · до 2 файлов · до 10 МБ'), findsOneWidget);
    await t.tap(find.text('Выбрать файл'));
    await settle(t);
    expect(find.textContaining('Задание не примет: отчёт.docx'), findsOneWidget);
    expect(find.text('отчёт.zip'), findsOneWidget);
    await t.tap(find.text('Сдать'));
    await settle(t);
    final sent = bodies['POST /api/sdo/submit'] as Map;
    expect(sent['deadline_id'], 7);
    expect(sent['files'], [
      {
        'name': 'отчёт.zip',
        'data': base64Encode([3, 4, 5]),
      },
    ]);
    expect(find.text('Сдано'), findsOneWidget);
    expect(find.text('Отправлено для оценивания'), findsOneWidget);
  });
}
