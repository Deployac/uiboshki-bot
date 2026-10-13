// Клавиатура в помощнике — как в приложении Claude (Никита, 12.10: «чтоб
// можно было норм листать чат с открытой клавиатурой но и свернуть
// клавиатуру»): прокрутка её не убирает, палец до поля ввода, смахивание
// поля вниз и нажатие на переписку — убирают; низ переписки не уезжает.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/screens/chat.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

Widget host(Widget child) => AppStyle(
  p: Palette.notebook,
  font: FontChoice.book,
  design2: false,
  child: MaterialApp(home: child),
);

/// Длинный разговор, чтобы было что листать.
Map<String, Object> longChat() => {
  chatsStoreKey: jsonEncode({
    'current': 'a',
    'chats': [
      {
        'id': 'a',
        'title': 'Вопрос 0',
        'updated': DateTime(2026, 10, 12, 10).millisecondsSinceEpoch,
        'subject': '',
        'log': [
          for (var i = 0; i < 12; i++) ...[
            {'role': 'user', 'content': 'Вопрос $i'},
            {'role': 'assistant', 'content': 'Ответ $i: ${'много текста ' * 20}'},
          ],
        ],
      },
    ],
  }),
};

bool typing(WidgetTester t) => t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

Future<void> open(WidgetTester t) async {
  phone(t);
  SharedPreferences.setMockInitialValues(longChat());
  await t.pumpWidget(host(ChatScreen(api: fakeApi())));
  await settle(t);
  await t.tap(find.byType(TextField));
  await settle(t);
  expect(typing(t), isTrue);
}

ScrollPosition pos(WidgetTester t) => t.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets('переписка листается, клавиатура остаётся', (t) async {
    await open(t);
    final before = pos(t).pixels;
    final list = find.byType(ListView);
    await t.drag(list, const Offset(0, 300)); // вверх по разговору
    await settle(t);
    expect(pos(t).pixels, lessThan(before));
    expect(typing(t), isTrue);
    await t.drag(list, const Offset(0, -200));
    await settle(t);
    expect(typing(t), isTrue);
  });

  testWidgets('палец довели до поля ввода — клавиатура уходит', (t) async {
    await open(t);
    final field = t.getRect(find.byType(TextField));
    final g = await t.startGesture(Offset(field.center.dx, field.top - 200));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 25));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t);
    expect(typing(t), isFalse);
  });

  testWidgets('поле ввода смахнули вниз — клавиатура уходит', (t) async {
    await open(t);
    final field = t.getRect(find.byType(TextField));
    final g = await t.startGesture(field.center);
    await g.moveBy(const Offset(0, 15));
    await t.pump();
    expect(typing(t), isTrue); // чуть сдвинул — ещё не смахнул
    await g.moveBy(const Offset(0, 20));
    await g.up();
    await settle(t);
    expect(typing(t), isFalse);
  });

  testWidgets('нажатие на переписку убирает клавиатуру', (t) async {
    await open(t);
    await t.tap(find.text('Вопрос 11'));
    await settle(t);
    expect(typing(t), isFalse);
  });

  testWidgets('клавиатура выехала внизу переписки — последний ответ виден', (t) async {
    await open(t);
    pos(t).jumpTo(pos(t).maxScrollExtent);
    await settle(t);
    t.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(t.view.resetViewInsets);
    await settle(t);
    expect(pos(t).pixels, pos(t).maxScrollExtent);
    expect(find.text('Вопрос 11').hitTestable(), findsOneWidget);
  });
}
