// Иконка приложения на выбор (5.79, второй круг дизайна, Никита 12.10):
// секция в «Оформлении» только на Android и iPhone, выбор идёт в канал
// uiboshki/icon, «Вернуть как было» и выключенный новый дизайн — обычная.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/main.dart';
import 'package:uiboshki/screens/look_screen.dart';
import 'package:uiboshki/theme/app_icon.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/theme/look.dart';

import 'fake_api.dart';
import 'util.dart';

const channel = MethodChannel('uiboshki/icon');

Map<String, Object?> meta(bool on) => {
  'GET /api/meta': {
    'api': 1,
    'server': '5.79.0',
    'min_client': {'web': '0.0.0', 'android': '0.0.0', 'ios': '0.0.0'},
    'login': ['telegram'],
    'features': {'groups': true, 'sessions': true, 'offline': true, 'design2': on},
    'links': {'bot': 'https://t.me/UiboshkiBot'},
  },
};

/// Подменный канал: помнит вызовы, «на телефоне» стоит [current].
class FakeIcons {
  String? current;
  final calls = <MethodCall>[];
  FakeIcons([this.current]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      switch (c.method) {
        case 'getIcon':
          return current;
        case 'setIcon':
          current = c.arguments as String?;
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
  }

  List<Object?> get sets => [
    for (final c in calls)
      if (c.method == 'setIcon') c.arguments,
  ];
}

Future<void> openLook(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('Ещё'));
  await settle(t);
  await t.tap(find.text('Оформление'));
  await settle(t);
  expect(find.byType(LookScreen), findsOneWidget);
}

Future<void> reach(WidgetTester t, String key) async {
  final list = find.descendant(of: find.byType(LookScreen), matching: find.byType(Scrollable)).first;
  await t.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: list);
  await settle(t);
}

AppStyle styleOf(WidgetTester t) => AppStyle.of(t.element(find.byType(Scaffold).first));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  testWidgets('на телефоне — выбор иконки: в канал и в настройки; «Вернуть как было» — обычная', (t) async {
    phone(t);
    final fake = FakeIcons();
    await t.pumpWidget(UiboApp(api: fakeApi(overrides: meta(true)), design2: true));
    await settle(t);
    expect(fake.sets, isEmpty); // на телефоне и так обычная — не трогаем
    await openLook(t);

    for (final i in AppIcon.values) {
      await reach(t, 'look:icon:${i.name}');
    }
    await t.tap(find.byKey(const Key('look:icon:sunset')));
    await settle(t);
    expect(fake.sets, ['sunset']);
    expect(fake.current, 'sunset');
    expect(styleOf(t).look.icon, AppIcon.sunset);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('uib_look_icon'), 'sunset');
    // подпись про ярлык — только на Android
    expect(
      find.textContaining('ярлык на рабочем столе'),
      defaultTargetPlatform == TargetPlatform.android ? findsOneWidget : findsNothing,
    );

    await reach(t, 'look:reset');
    await t.tap(find.byKey(const Key('look:reset')));
    await settle(t);
    expect(fake.sets, ['sunset', null]);
    expect(fake.current, isNull);
    expect(styleOf(t).look, Look.classic);
    expect(prefs.getString('uib_look_icon'), 'classic');
  }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('сервер выключил новый дизайн — при запуске обычная иконка, выбор помнится', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({'uib_toured': true, 'uib_look_icon': 'depth'});
    final prefs = await SharedPreferences.getInstance();
    final fake = FakeIcons('depth');
    await t.pumpWidget(
      UiboApp(
        api: fakeApi(overrides: meta(false)),
        design2: true,
        look: Look.fromPrefs(prefs),
      ),
    );
    await settle(t);
    expect(fake.sets, [null]);
    expect(fake.current, isNull);
    expect(prefs.getString('uib_look_icon'), 'depth'); // включат снова — вернётся
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('новый дизайн включён — выбранная иконка остаётся, лишних вызовов нет', (t) async {
    phone(t);
    final fake = FakeIcons('depth');
    await t.pumpWidget(
      UiboApp(
        api: fakeApi(overrides: meta(true)),
        design2: true,
        look: const Look(icon: AppIcon.depth),
      ),
    );
    await settle(t);
    expect(fake.calls.map((c) => c.method), ['getIcon']);
    expect(fake.sets, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('не телефон — секции нет', (t) async {
    phone(t);
    await t.pumpWidget(UiboApp(api: fakeApi(overrides: meta(true)), design2: true));
    await settle(t);
    await openLook(t);
    await reach(t, 'look:cheer:capy');
    expect(find.text('иконка приложения'), findsNothing);
    expect(find.byKey(const Key('look:icon:classic')), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('без канала (старая сборка) — выбор не падает', (t) async {
    phone(t);
    await t.pumpWidget(UiboApp(api: fakeApi(overrides: meta(true)), design2: true));
    await settle(t);
    await openLook(t);
    await reach(t, 'look:icon:library');
    await t.tap(find.byKey(const Key('look:icon:library')));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(styleOf(t).look.icon, AppIcon.library);
    await t.runAsync(() => syncAppIcon(AppIcon.classic)); // и напрямую — тихо
  });
}
