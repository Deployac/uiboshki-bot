import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/main.dart';
import 'package:uiboshki/screens/notify.dart';
import 'package:uiboshki/screens/security.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

Widget _wrap(Widget child) => AppStyle(
  p: Palette.depth,
  font: FontChoice.book,
  child: MaterialApp(home: child),
);

const _sessions = {
  'items': [
    {'id': 11, 'device': 'Капибара · Android', 'last_seen': '2026-10-08 07:00:00', 'current': true},
    {'id': 12, 'device': 'Chrome · Windows', 'last_seen': '2026-10-01 12:00:00', 'current': false},
  ],
};

const _identities = {
  'items': [],
  'available': [
    {'id': 'vk', 'name': 'VK ID'},
    {'id': 'yandex', 'name': 'Яндекс ID'},
  ],
  'telegram': true,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('уведомления: выключатель и день недели уходят на сервер', (t) async {
    phone(t);
    final asked = <String>[];
    final bodies = <String, Object?>{};
    final api = fakeApi(requests: asked, bodies: bodies);
    await t.pumpWidget(_wrap(NotifyScreen(api: api)));
    await settle(t);
    expect(asked, contains('GET /api/notify'));
    expect(find.text('Утреннее расписание'), findsOneWidget);
    expect(find.textContaining('в браузере; в приложении — скоро'), findsOneWidget);

    await t.tap(find.byKey(const Key('notify:weather')));
    await settle(t);
    expect(bodies['POST /api/notify'], {
      'prefs': {'weather': false},
    });

    await t.tap(find.byKey(const Key('days:morning_days:6')));
    await settle(t);
    expect(bodies['POST /api/notify'], {
      'prefs': {
        'morning_days': [0, 1, 2, 3, 4, 5],
      },
    });

    // сценарий перед первой парой — пресет «30 мин»
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await settle(t);
    await t.tap(find.byKey(const Key('remind:remind_first:30 мин')));
    await settle(t);
    expect(bodies['POST /api/notify'], {
      'prefs': {'remind_first': 30},
    });

    // общий выключатель — карточки прячутся
    await t.ensureVisible(find.byKey(const Key('notify:subscribed')));
    await settle(t);
    await t.tap(find.byKey(const Key('notify:subscribed')));
    await settle(t);
    expect(bodies['POST /api/notify'], {'subscribed': false});
    expect(find.text('Утреннее расписание'), findsNothing);
  });

  testWidgets('безопасность: устройства, выйти на чужом и везде', (t) async {
    phone(t);
    final asked = <String>[];
    var loggedOut = 0;
    final api = fakeApi(requests: asked, overrides: {'GET /api/auth/sessions': _sessions});
    await t.pumpWidget(_wrap(SecurityScreen(api: api, onLogout: () => loggedOut++)));
    await settle(t);
    expect(find.text('Капибара · Android · это'), findsOneWidget);
    expect(find.text('Chrome · Windows'), findsOneWidget);
    expect(find.text('Как защищены данные'), findsOneWidget);

    await t.tap(find.text('Выйти').at(1)); // чужое устройство — остаёмся
    await settle(t);
    expect(asked, contains('DELETE /api/auth/sessions/12'));
    expect(loggedOut, 0);

    await t.tap(find.text('Выйти везде'));
    await settle(t);
    await t.tap(find.text('Выйти везде').last); // подтверждение
    await settle(t);
    expect(asked, contains('POST /api/auth/logout?everywhere=true'));
    expect(loggedOut, 1);
  });

  testWidgets('безопасность: привязать VK — ссылка в браузер, отвязать', (t) async {
    phone(t);
    final asked = <String>[];
    final bodies = <String, Object?>{};
    Uri? opened;
    final api = fakeApi(
      requests: asked,
      bodies: bodies,
      overrides: {
        'GET /api/auth/sessions': _sessions,
        'GET /api/auth/identities': _identities,
        'POST /api/auth/vk/link': {'url': 'https://id.vk.com/authorize?state=l1'},
      },
    );
    await t.pumpWidget(_wrap(SecurityScreen(api: api, onLogout: () {}, open: (u) async => opened = u)));
    await settle(t);
    expect(find.text('Вход без Telegram'), findsOneWidget);
    await t.tap(find.text('Привязать').first);
    await settle(t);
    expect(bodies['POST /api/auth/vk/link'], {'client': 'app'});
    expect(opened.toString(), 'https://id.vk.com/authorize?state=l1');

    // привязанный — кнопка «Отвязать»
    final linked = fakeApi(
      requests: asked,
      overrides: {
        'GET /api/auth/sessions': _sessions,
        'GET /api/auth/identities': {
          ..._identities,
          'items': [
            {'provider': 'yandex', 'name': 'Аня', 'title': 'Яндекс ID'},
          ],
        },
      },
    );
    await t.pumpWidget(_wrap(SecurityScreen(key: const Key('2'), api: linked, onLogout: () {})));
    await settle(t);
    await t.tap(find.text('Отвязать'));
    await settle(t);
    expect(asked, contains('DELETE /api/auth/identities/yandex'));
  });

  testWidgets('«Ещё»: предмет по выбору — «Хожу» уходит на сервер', (t) async {
    SharedPreferences.setMockInitialValues({'uib_toured': true});
    phone(t);
    final bodies = <String, Object?>{};
    final api = fakeApi(
      bodies: bodies,
      overrides: {
        'GET /api/optional': {
          'pending': ['Военная кафедра'],
          'answers': {},
        },
      },
    );
    await t.pumpWidget(UiboApp(api: api));
    await settle(t);
    await t.tap(find.bySemanticsLabel('Ещё'));
    await settle(t);
    await t.ensureVisible(find.text('Хожу'));
    await settle(t);
    await t.tap(find.text('Хожу'));
    await settle(t);
    expect(bodies['POST /api/optional'], {'subject': 'Военная кафедра', 'attend': true});
    expect(find.text('Хожу — пары в расписании'), findsOneWidget);
    expect(find.text('Уведомления'), findsOneWidget);
    expect(find.text('Безопасность'), findsOneWidget);
  });
}
