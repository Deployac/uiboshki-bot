// «Вечерняя сводка» в уведомлениях (Никита 12.10): один пункт с переключателем
// и временем; только при новом дизайне и если сервер отдал ключ evening.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/screens/notify.dart';
import 'package:uiboshki/theme/app_theme.dart';

import 'fake_api.dart';
import 'util.dart';

Widget _wrap(Widget child, {bool design2 = true}) => AppStyle(
  p: Palette.depth,
  font: FontChoice.book,
  design2: design2,
  child: MaterialApp(home: child),
);

Future<void> _toEnd(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.drag(find.byType(ListView), const Offset(0, -500));
    await settle(t);
  }
}

void main() {
  testWidgets('включить и выбрать время — уходит на сервер', (t) async {
    phone(t);
    final bodies = <String, Object?>{};
    await t.pumpWidget(_wrap(NotifyScreen(api: fakeApi(bodies: bodies))));
    await settle(t);
    await _toEnd(t);
    expect(find.text('Вечерняя сводка'), findsOneWidget);
    expect(find.text('Пары и сроки на завтра · 20:00'), findsOneWidget);
    expect(find.byKey(const Key('evening:21:00')), findsNothing); // выключено — времени не видно

    await t.tap(find.byKey(const Key('notify:evening')));
    await settle(t);
    expect(bodies['POST /api/notify'], {
      'prefs': {'evening': true},
    });
    await _toEnd(t);
    await t.tap(find.byKey(const Key('evening:21:00')));
    await settle(t);
    expect(bodies['POST /api/notify'], {
      'prefs': {'evening_time': '21:00'},
    });
    expect(find.text('Пары и сроки на завтра · 21:00'), findsOneWidget);
  });

  testWidgets('старый дизайн или сервер без ключа — пункта нет', (t) async {
    phone(t);
    await t.pumpWidget(_wrap(NotifyScreen(api: fakeApi()), design2: false));
    await settle(t);
    await _toEnd(t);
    expect(find.text('Новые задания'), findsOneWidget);
    expect(find.text('Вечерняя сводка'), findsNothing);

    final fx = demoFixtures()['GET /api/notify'] as Map<String, dynamic>;
    final prefs = Map<String, dynamic>.from(fx['prefs'] as Map)
      ..remove('evening')
      ..remove('evening_time');
    await t.pumpWidget(
      _wrap(
        NotifyScreen(
          key: const Key('no-evening'), // новый экран, а не прежний с загруженным ответом
          api: fakeApi(
            overrides: {
              'GET /api/notify': {...fx, 'prefs': prefs},
            },
          ),
        ),
      ),
    );
    await settle(t);
    await _toEnd(t);
    expect(find.text('Новые задания'), findsOneWidget);
    expect(find.text('Вечерняя сводка'), findsNothing);
  });

  test('своё время — до получаса, 17:00–23:30', () {
    expect(eveningSlot(20, 10), '20:00');
    expect(eveningSlot(20, 20), '20:30');
    expect(eveningSlot(21, 50), '22:00');
    expect(eveningSlot(9, 0), '17:00');
    expect(eveningSlot(23, 55), '23:30');
  });
}
