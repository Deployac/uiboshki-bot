// «Прошлые чаты» помощника — как в WebApp (Никита, 12.10: «Где предыдущие
// чаты? В тг веб эп было это»): до 20 разговоров на телефоне, список листом
// снизу, открыть, удалить, новый; прежняя одна история переезжает первым чатом.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/screens/chat.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

Widget host(Widget child, {bool design2 = false}) => AppStyle(
  p: Palette.notebook,
  font: FontChoice.book,
  design2: design2,
  child: MaterialApp(home: child),
);

Future<Map<String, dynamic>> stored() async =>
    jsonDecode((await SharedPreferences.getInstance()).getString(chatsStoreKey)!) as Map<String, dynamic>;

Future<List<String>> titles() async => [for (final c in (await stored())['chats'] as List) '${c['title']}'];

Future<void> ask(WidgetTester t, String q) async {
  await t.enterText(find.byType(TextField), q);
  await t.tap(find.byTooltip('Отправить'));
  await settle(t);
}

Map<String, dynamic> chat(String id, String q, {int ago = 0}) => {
  'id': id,
  'title': q,
  'updated': DateTime(2026, 10, 12, 10).subtract(Duration(hours: ago)).millisecondsSinceEpoch,
  'subject': '',
  'log': [
    {'role': 'user', 'content': q},
    {'role': 'assistant', 'content': 'Ответ на «$q»'},
  ],
};

Finder inChat(String id, Finder f) => find.descendant(of: find.byKey(ValueKey('chat:$id')), matching: f);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('прежняя одна история переезжает первым чатом и открывается', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({
      chatLegacyKey: jsonEncode({
        'log': [
          {'role': 'user', 'content': 'Что такое NPV?'},
          {'role': 'assistant', 'content': 'Чистая приведённая стоимость.'},
        ],
        'subject': 'Анализ данных',
      }),
    });
    await t.pumpWidget(host(ChatScreen(api: fakeApi())));
    await settle(t);
    expect(find.text('Что такое NPV?'), findsOneWidget);
    expect(find.text('Чистая приведённая стоимость.'), findsOneWidget);
    expect(find.text('Анализ данных'), findsOneWidget); // предмет чата — на чипе

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(chatLegacyKey), isNull);
    final s = await stored();
    final c = (s['chats'] as List).single as Map;
    expect(c['title'], 'Что такое NPV?');
    expect(c['subject'], 'Анализ данных');
    expect((c['log'] as List).length, 2);
    expect(s['current'], c['id']);

    await t.tap(find.byTooltip('Прошлые чаты'));
    await settle(t);
    expect(find.text('Прошлые чаты'), findsOneWidget);
    expect(inChat('${c['id']}', find.textContaining('2 сообщения · Анализ данных')), findsOneWidget);
  });

  testWidgets('несколько чатов: сохраняются, переключаются, после перезапуска — открытый', (t) async {
    phone(t);
    final bodies = <String, Object?>{};
    await t.pumpWidget(host(ChatScreen(api: fakeApi(bodies: bodies))));
    await settle(t);
    expect(find.byTooltip('Прошлые чаты'), findsNothing); // чатов ещё нет

    await ask(t, 'Вопрос про NPV');
    await t.tap(find.byTooltip('Новый чат'));
    await settle(t);
    expect(find.text('Вопрос про NPV'), findsNothing);
    await ask(t, 'Вопрос про ROI');
    expect(await titles(), ['Вопрос про ROI', 'Вопрос про NPV']);
    final ids = [for (final c in (await stored())['chats'] as List) '${c['id']}'];
    expect((await stored())['current'], ids.first);

    await t.tap(find.byTooltip('Прошлые чаты'));
    await settle(t);
    expect(find.text('Вопрос про NPV'), findsOneWidget); // только в списке
    expect(find.text('Вопрос про ROI'), findsNWidgets(2)); // в ленте и в списке
    expect(find.byKey(const Key('chats:new')), findsOneWidget);
    expect(find.textContaining('сегодня, '), findsNWidgets(2));
    await t.tap(find.text('Вопрос про NPV'));
    await settle(t);
    expect(find.text('Прошлые чаты'), findsNothing);
    expect(find.text('Вопрос про NPV'), findsOneWidget);
    expect(find.text('Вопрос про ROI'), findsNothing);
    expect((await stored())['current'], ids.last);

    // следующий вопрос — с историей этого чата, а не того
    await ask(t, 'А подробнее?');
    final history = (bodies['POST /api/chat'] as Map)['history'] as List;
    expect([for (final m in history) m['content']], contains('Вопрос про NPV'));
    expect([for (final m in history) m['content']], isNot(contains('Вопрос про ROI')));
    expect(await titles(), ['Вопрос про NPV', 'Вопрос про ROI']); // свежий — наверх

    // «перезапуск» — открывается тот, что был открыт
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(ChatScreen(api: fakeApi())));
    await settle(t);
    expect(find.text('А подробнее?'), findsOneWidget);
    expect(find.text('Вопрос про ROI'), findsNothing);

    // «Новый чат» из листа, перезапуск — открывается пустой
    await t.tap(find.byTooltip('Прошлые чаты'));
    await settle(t);
    await t.tap(find.byKey(const Key('chats:new')));
    await settle(t);
    expect(find.text('А подробнее?'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(ChatScreen(api: fakeApi())));
    await settle(t);
    expect(find.text('А подробнее?'), findsNothing);
    expect(find.textContaining('Отвечает по лекциям'), findsOneWidget);
    expect(find.byTooltip('Прошлые чаты'), findsOneWidget);
  });

  testWidgets('удалить чат: крестиком и смахиванием; открытый — экран с нуля', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({
      chatsStoreKey: jsonEncode({
        'chats': [
          chat('c1', 'Первый вопрос'),
          chat('c2', 'Второй вопрос', ago: 1),
          chat('c3', 'Третий вопрос', ago: 30),
        ],
        'current': 'c2',
      }),
    });
    await t.pumpWidget(host(ChatScreen(api: fakeApi())));
    await settle(t);
    expect(find.text('Второй вопрос'), findsOneWidget);

    await t.tap(find.byTooltip('Прошлые чаты'));
    await settle(t);
    expect(find.text('Третий вопрос'), findsOneWidget);
    await t.tap(inChat('c1', find.byTooltip('Удалить чат')));
    await settle(t);
    expect(find.text('Первый вопрос'), findsNothing);
    expect(await titles(), ['Второй вопрос', 'Третий вопрос']);

    // открытый — смахнуть влево
    await t.drag(find.byKey(const ValueKey('chat-swipe:c2')), const Offset(-600, 0));
    await settle(t);
    expect(await titles(), ['Третий вопрос']);
    expect((await stored())['current'], '');
    expect(find.text('Второй вопрос'), findsNothing); // и из ленты

    // последний — лист закрывается, кнопки списка больше нет
    await t.tap(inChat('c3', find.byTooltip('Удалить чат')));
    await settle(t);
    expect(find.text('Прошлые чаты'), findsNothing);
    expect(find.byTooltip('Прошлые чаты'), findsNothing);
    expect(await titles(), isEmpty);
    expect(find.textContaining('Отвечает по лекциям'), findsOneWidget);
  });

  testWidgets('хранится не больше 20 чатов — старый уходит', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({
      chatsStoreKey: jsonEncode({
        'chats': [for (var i = 0; i < chatsMax; i++) chat('c$i', 'Вопрос $i', ago: i)],
        'current': '',
      }),
    });
    await t.pumpWidget(host(ChatScreen(api: fakeApi())));
    await settle(t);
    expect(find.textContaining('Отвечает по лекциям'), findsOneWidget); // был «Новый чат»
    await ask(t, 'Двадцать первый');
    final list = await titles();
    expect(list.length, chatsMax);
    expect(list.first, 'Двадцать первый');
    expect(list, isNot(contains('Вопрос ${chatsMax - 1}')));
    expect(list, contains('Вопрос ${chatsMax - 2}'));
  });

  testWidgets('ответ, пришедший после ухода в новый чат, — в свой чат', (t) async {
    phone(t);
    await t.pumpWidget(host(ChatScreen(api: fakeApi(delay: () => const Duration(seconds: 2)))));
    await t.pump(const Duration(seconds: 3));
    await t.enterText(find.byType(TextField), 'Долгий вопрос');
    await t.tap(find.byTooltip('Отправить'));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byTooltip('Новый чат'));
    await t.pump(const Duration(seconds: 3));
    await settle(t);
    expect(find.text('Долгий вопрос'), findsNothing);
    expect(find.textContaining('все KPI — метрики', findRichText: true), findsNothing);
    final s = await stored();
    expect(s['current'], '');
    final log = ((s['chats'] as List).single as Map)['log'] as List;
    expect([for (final m in log) m['role']], ['user', 'assistant']);
    expect(log.first['content'], 'Долгий вопрос');
  });

  testWidgets('лист чатов в новом дизайне', (t) async {
    phone(t);
    SharedPreferences.setMockInitialValues({
      chatsStoreKey: jsonEncode({
        'chats': [chat('c1', 'Очень длинный вопрос про метрики, KPI и всё, что с ними связано на практике')],
        'current': 'c1',
      }),
    });
    await t.pumpWidget(host(ChatScreen(api: fakeApi()), design2: true));
    await settle(t);
    await t.tap(find.byTooltip('Прошлые чаты'));
    await settle(t);
    expect(find.text('Прошлые чаты'), findsOneWidget);
    expect(find.byKey(const Key('chats:new')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('узкий экран, крупный шрифт, длинный предмет — шапка не вылезает', (t) async {
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = const Size(640, 1136);
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({
      chatsStoreKey: jsonEncode({
        'chats': [
          {...chat('c1', 'Вопрос'), 'subject': 'Анализ и диагностика финансово-хозяйственной деятельности предприятия'},
        ],
        'current': 'c1',
      }),
    });
    await t.pumpWidget(host(ChatScreen(api: fakeApi())));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.byTooltip('Прошлые чаты'), findsOneWidget);
    expect(find.byTooltip('Новый чат'), findsOneWidget);
    expect(t.getRect(find.byType(ActionChip).first).right, lessThanOrEqualTo(320));
  });

  test('заголовок — начало первого вопроса, дата — по-человечески', () {
    expect(chatTitle([]), 'Новый чат');
    expect(
      chatTitle([
        {'role': 'assistant', 'content': 'Привет'},
        {'role': 'user', 'content': 'а' * 80},
      ]),
      'а' * 60,
    );
    final today = DateTime(2026, 10, 12, 15);
    expect(chatWhen(DateTime(2026, 10, 12, 9, 5), today), 'сегодня, 09:05');
    expect(chatWhen(DateTime(2026, 10, 11, 23), today), 'вчера');
    expect(chatWhen(DateTime(2026, 9, 3), today), '3 сен');
    expect(chatWhen(DateTime(2025, 12, 30), today), '30 дек 2025');
  });
}
