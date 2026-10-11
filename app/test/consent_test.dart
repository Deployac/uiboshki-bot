// 152-ФЗ (legal.dart): галочка не стоит, «Продолжить» неактивна без неё;
// ссылка открывает текст; согласие уходит на сервер; удаление данных.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/screens/legal.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

const _doc = {
  'name': 'consent',
  'title': 'Согласие на обработку персональных данных',
  'version': '1',
  'date': '11.10.2026',
  'lead': 'Ставя галочку…',
  'sections': [
    {
      'title': 'Кому передаются',
      'blocks': [
        {'p': 'Абзац'},
        {'ul': ['Railway (США) — хостинг', 'Telegram — сообщения']},
      ],
    },
  ],
};

Widget _wrap(Widget child) => AppStyle(
  p: Palette.notebook,
  font: FontChoice.strict,
  child: MaterialApp(home: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('первый вход: без галочки дальше нельзя, ссылка открывает текст', (t) async {
    phone(t);
    final asked = <String>[];
    final bodies = <String, Object?>{};
    final api = fakeApi(
      requests: asked,
      bodies: bodies,
      overrides: {
        'GET /api/legal/consent': _doc,
        'POST /api/consent': {'version': '1', 'date': '11.10.2026', 'pd': true, 'sdo': false},
      },
    );
    await t.pumpWidget(_wrap(ConsentScreen(api: api)));
    await settle(t);
    final go = find.widgetWithText(FilledButton, 'Продолжить');
    expect(t.widget<FilledButton>(go).onPressed, isNull); // галочка по умолчанию не стоит

    // синяя ссылка «согласие на обработку…» — текст поверх, галочка не ставится
    await t.tapOnText(find.textRange.ofSubstring('согласие на обработку персональных данных'));
    await settle(t);
    expect(find.text('Railway (США) — хостинг'), findsOneWidget);
    expect(asked, contains('GET /api/legal/consent'));
    await t.tap(find.byTooltip('Назад'));
    await settle(t);
    expect(t.widget<FilledButton>(go).onPressed, isNull);

    await t.tap(find.descendant(of: find.byType(ConsentCheck), matching: find.byType(AnimatedContainer)));
    await settle(t);
    expect(t.widget<FilledButton>(go).onPressed, isNotNull);
    await t.tap(go);
    await settle(t);
    expect(bodies['POST /api/consent'], {'kind': 'pd'});
  });

  testWidgets('удалить все мои данные: с подтверждением, потом выход', (t) async {
    phone(t);
    final asked = <String>[];
    final api = fakeApi(requests: asked, overrides: {'POST /api/me/delete': {'ok': true}});
    late BuildContext ctx;
    await t.pumpWidget(_wrap(Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    bool? done;
    deleteMyData(ctx, api).then((v) => done = v);
    await settle(t);
    await t.tap(find.text('Удалить всё'));
    await settle(t);
    await t.pump(const Duration(seconds: 5)); // тост уходит
    expect(done, isTrue);
    expect(asked, contains('POST /api/me/delete'));
    expect(api.token, isNull);
  });
}
