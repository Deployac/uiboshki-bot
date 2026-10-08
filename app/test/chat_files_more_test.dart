import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/screens/chat.dart';
import 'package:uiboshki/screens/files.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

Widget host(Widget child) => AppStyle(
  p: Palette.notebook,
  font: FontChoice.book,
  child: MaterialApp(home: child),
);

const _answer = {'content': 'Во втором разделе — про KPI.', 'html': 'Во втором разделе — про KPI.'};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('вложение: уходит base64, текст документа помнится в следующих вопросах', (t) async {
    phone(t);
    final bodies = <String, Object?>{};
    final api = fakeApi(
      bodies: bodies,
      overrides: {
        'POST /api/chat': {..._answer, 'file_text': '=== Файл «plan.pdf» ===\nРаздел 2. KPI'},
      },
    );
    final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4 план'));
    await t.pumpWidget(
      host(ChatScreen(api: api, pick: () async => ChatAttachment('plan.pdf', 'application/pdf', bytes))),
    );
    await settle(t);

    await t.tap(find.byTooltip('Прикрепить фото или файл'));
    await settle(t);
    expect(find.text('прикреплено: plan.pdf'), findsOneWidget);
    // крестик убирает вложение
    await t.tap(find.byTooltip('Убрать'));
    await settle(t);
    expect(find.text('прикреплено: plan.pdf'), findsNothing);

    await t.tap(find.byTooltip('Прикрепить фото или файл'));
    await settle(t);
    await t.tap(find.byTooltip('Отправить')); // без текста — «Разбери этот файл.»
    await settle(t);
    final first = bodies['POST /api/chat'] as Map;
    expect(first['attachment'], {'name': 'plan.pdf', 'mime': 'application/pdf', 'data': base64Encode(bytes)});
    expect((first['history'] as List).last['content'], 'Разбери этот файл.');
    expect(find.text('прикреплено: plan.pdf'), findsNothing);
    expect(find.text('plan.pdf'), findsOneWidget); // в пузыре вопроса

    await t.enterText(find.byType(TextField), 'А что во втором разделе?');
    await t.tap(find.byTooltip('Отправить'));
    await settle(t);
    final second = bodies['POST /api/chat'] as Map;
    expect(second.containsKey('attachment'), isFalse);
    final history = second['history'] as List;
    expect(history.first['content'], contains('Раздел 2. KPI'));
    expect(history.last['content'], 'А что во втором разделе?');
  });

  testWidgets('вложение больше 10 МБ не прикрепляется', (t) async {
    phone(t);
    final big = Uint8List(maxAttachmentBytes + 1);
    await t.pumpWidget(
      host(ChatScreen(api: fakeApi(), pick: () async => ChatAttachment('big.pdf', 'application/pdf', big))),
    );
    await settle(t);
    await t.tap(find.byTooltip('Прикрепить фото или файл'));
    await settle(t);
    expect(find.text('Файл больше 10 МБ — не пролезет.'), findsOneWidget);
  });

  testWidgets('источник под ответом → страница лекции, «Весь файл» → лист файла', (t) async {
    phone(t);
    final asked = <String>[];
    await t.pumpWidget(host(ChatScreen(api: fakeApi(requests: asked))));
    await settle(t);
    await t.enterText(find.byType(TextField), 'Чем метрика отличается от KPI?');
    await t.tap(find.byTooltip('Отправить'));
    await settle(t);
    await t.tap(find.text('Лекция 4. Метрики и KPI · стр. 3'));
    await settle(t);
    expect(asked, contains('GET /api/files/4/page/3'));
    expect(find.text('Страница 3 из 18'), findsOneWidget);
    expect(find.textContaining('KPI — ключевая метрика'), findsOneWidget);
    final img = t.widget<Image>(find.byType(Image));
    expect((img.image as NetworkImage).url, pageImageUrl('site/slide-3.jpg'));
    expect(pageImageUrl('https://x.ru/pg/4/3.jpg'), 'https://x.ru/pg/4/3.jpg');

    await t.tap(find.byTooltip('Следующая'));
    await settle(t);
    expect(asked, contains('GET /api/files/4/page/4'));

    await t.tap(find.text('Весь файл'));
    await settle(t);
    expect(find.text('Скачать'), findsOneWidget);
    expect(find.text('Лекция 4. Метрики и KPI'), findsOneWidget);
  });

  testWidgets('история чата сохраняется, «Новый чат» начинает с нуля', (t) async {
    phone(t);
    await t.pumpWidget(host(ChatScreen(api: fakeApi())));
    await settle(t);
    await t.enterText(find.byType(TextField), 'Чем метрика отличается от KPI?');
    await t.tap(find.byTooltip('Отправить'));
    await settle(t);

    // «перезапуск»: новый экран читает историю с телефона
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(ChatScreen(api: fakeApi())));
    await settle(t);
    expect(find.text('Чем метрика отличается от KPI?'), findsOneWidget);
    expect(find.textContaining('все KPI — метрики', findRichText: true), findsOneWidget);

    await t.tap(find.byTooltip('Новый чат'));
    await settle(t);
    expect(find.text('Чем метрика отличается от KPI?'), findsOneWidget); // осталась только подсказка
    expect(find.textContaining('все KPI — метрики', findRichText: true), findsNothing);
    expect((await SharedPreferences.getInstance()).getString(chatStoreKey), isNull);
  });

  testWidgets('файлы: поиск по названию и в тексте лекций → страница', (t) async {
    phone(t);
    final asked = <String>[];
    final api = fakeApi(
      requests: asked,
      overrides: {
        'GET /api/files?q=KPI': {
          'items': [
            {
              'id': 4,
              'title': 'Лекция 4. Метрики и KPI',
              'subject': 'Основы бизнес-анализа в ИТ-сфере',
              'file_name': 'lk4.pdf',
              'has_text': true,
              'category': 'lecture',
            },
          ],
        },
        'GET /api/lecture-search?q=KPI': {
          'ready': true,
          'items': [
            {
              'file_id': 4,
              'title': 'Лекция 4. Метрики и KPI',
              'subject': 'Основы бизнес-анализа в ИТ-сфере',
              'place': 'стр. 5',
              'page': 5,
              'snippet': 'Хороший KPI — измеримый и ограниченный по времени',
            },
          ],
        },
      },
    );
    await t.pumpWidget(host(FilesScreen(api: api)));
    await settle(t);
    await t.enterText(find.byType(TextField), 'KPI');
    await settle(t);
    expect(asked, containsAll(['GET /api/files?q=KPI', 'GET /api/lecture-search?q=KPI']));
    expect(find.text('Файлы · 1'), findsOneWidget);
    expect(find.text('В тексте лекций'), findsOneWidget);
    expect(find.textContaining('Хороший KPI', findRichText: true), findsOneWidget);

    await t.tap(find.textContaining('Хороший KPI', findRichText: true));
    await settle(t);
    expect(asked, contains('GET /api/files/4/page/5'));
    expect(find.text('Страница 5 из 18'), findsOneWidget);
  });

  testWidgets('файлы: ничего не нашлось', (t) async {
    phone(t);
    final api = fakeApi(
      overrides: {
        'GET /api/files?q=zzz': {'items': []},
        'GET /api/lecture-search?q=zzz': {'ready': false, 'items': []},
      },
    );
    await t.pumpWidget(host(FilesScreen(api: api)));
    await settle(t);
    await t.enterText(find.byType(TextField), 'zzz');
    await settle(t);
    expect(find.text('Ничего не нашлось'), findsOneWidget);
    expect(find.text('Тексты лекций ещё индексируются.'), findsOneWidget);
  });

  test('корни слов запроса и подсветка в отрывке', () {
    expect(queryStems('метрики и KPI'), ['метри', 'kpi']);
    final span = markStems('Метрики и kpi', queryStems('метрика KPI'), const TextStyle(), const TextStyle());
    expect([for (final c in span.children!) (c as TextSpan).text], ['Метрики', ' и ', 'kpi']);
  });
}
