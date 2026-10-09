// Тема лекции строкой под номером (владелец, 09.10: «тему писать под
// „Лекция 1“») и одна строка на лекцию в PDF и презентации.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/screens/files.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

Widget _wrap(Widget child) => AppStyle(
  p: Palette.depth,
  font: FontChoice.book,
  child: MaterialApp(home: child),
);

FileItem _f(int id, String title, String name, {String head = '', String topic = ''}) => FileItem.fromJson({
  'id': id,
  'title': title,
  'head': head,
  'topic': topic,
  'subject': 'ОПД',
  'file_name': name,
  'category': 'lecture',
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('без head и topic (старый сервер) — название целиком', () {
    final f = FileItem.fromJson({'id': 1, 'title': 'Лекция 8. Риски', 'subject': 'ИБ'});
    expect(f.head, 'Лекция 8. Риски');
    expect(f.topic, '');
  });

  test('«Лекция 1» и «Лекция 1. Презентация» — одна строка', () {
    final rows = groupSameTitle([
      _f(1, 'Лекция 1', 'l1.pdf', head: 'Лекция 1'),
      _f(2, 'Лекция 1. Презентация', 'p1.pptx', head: 'Лекция 1'),
      _f(3, 'Лекция 2. Идея', 'l2.pdf', head: 'Лекция 2', topic: 'Идея'),
      _f(4, 'Лекция 2. Идея', 'p2.pptx', head: 'Лекция 2', topic: 'Идея'),
      _f(5, 'Лекция 2. Другое', 'x.pdf', head: 'Лекция 2', topic: 'Другое'),
    ]);
    expect(rows.map((r) => r.map((f) => f.id).toSet()).toList(), [
      {1, 2},
      {5},
      {3, 4},
    ]);
  });

  testWidgets('файлы предмета: тема строкой под «Лекция N», пара форматов — кнопкой', (t) async {
    phone(t);
    final files = [
      _f(1, 'Лекция 1. Предпринимательство', 'l1.pdf', head: 'Лекция 1', topic: 'Предпринимательство'),
      _f(2, 'Лекция 1. Предпринимательство', 'p1.pptx', head: 'Лекция 1', topic: 'Предпринимательство'),
      _f(3, 'Лекция 2', 'l2.pdf', head: 'Лекция 2'),
    ];
    await t.pumpWidget(_wrap(SubjectFilesScreen(api: fakeApi(), subject: 'ОПД', files: files)));
    await settle(t);
    expect(find.text('Лекция 1'), findsOneWidget);
    expect(find.text('Предпринимательство'), findsOneWidget);
    expect(find.text('Лекция 1. Предпринимательство'), findsNothing);
    expect(find.text('Лекция 2'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'PPTX'), findsOneWidget);
  });
}
