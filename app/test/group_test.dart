import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/main.dart';

import 'fake_api.dart';
import 'util.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  testWidgets('новый человек без группы — сначала выбор группы', (t) async {
    phone(t);
    final asked = <String>[];
    final bodies = <String, Object?>{};
    final group = <String, Object?>{'id': 222, 'first_name': 'Аня', 'group': null, 'plan': 'base'};
    final api = fakeApi(requests: asked, bodies: bodies, overrides: {'GET /api/me': group});
    await t.pumpWidget(UiboApp(api: api));
    await settle(t);
    expect(find.text('Из какой ты группы?'), findsOneWidget);
    await t.enterText(find.byType(EditableText).first, 'уибо-01');
    await settle(t);
    expect(asked, contains('GET /api/groups/search?q=%D1%83%D0%B8%D0%B1%D0%BE-01'));
    await t.tap(find.text('УИБО-01-24'));
    await settle(t);
    expect(bodies['POST /api/me/group'], {'id': 5001});
    expect(find.text('Из какой ты группы?'), findsNothing);
  });

  testWidgets('с группой — выбор не спрашивается, в «Ещё» её можно сменить', (t) async {
    phone(t);
    await t.pumpWidget(UiboApp(api: fakeApi()));
    await settle(t);
    expect(find.text('Из какой ты группы?'), findsNothing);
    await t.tap(find.bySemanticsLabel('Ещё'));
    await settle(t);
    await t.ensureVisible(find.byKey(const Key('more:group')));
    await settle(t);
    await t.tap(find.text('Группа'));
    await settle(t);
    expect(find.text('Из какой ты группы?'), findsOneWidget);
    expect(find.byTooltip('Назад'), findsOneWidget); // не первый вход — можно вернуться
  });
}
