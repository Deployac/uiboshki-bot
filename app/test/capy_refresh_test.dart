// Капибара при обновлении (26, «все это»): при первой загрузке — сцена с
// подписью вместо крутилки; потянул вниз — маленькая капибара без плашки,
// данные пришли — уехала; сцены по кругу, ночью — сон.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/capy.dart';
import 'package:uiboshki/widgets/capy_refresh.dart';
import 'package:uiboshki/widgets/common.dart';

import 'util.dart';

Widget host(Widget child, {Palette p = Palette.depth}) => AppStyle(
  p: p,
  font: FontChoice.book,
  child: MaterialApp(home: Scaffold(body: child)),
);

Widget list(Future<void> Function() onRefresh, {int? hour}) => host(
  CapyRefresh(
    onRefresh: onRefresh,
    hour: hour,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [for (var i = 0; i < 30; i++) ListTile(title: Text('строка $i'))],
    ),
  ),
);

Finder get card => find.byKey(const Key('capy:refresh'));

void main() {
  test('сцены идут по кругу, ночью — сон', () {
    CapyScenes.startAt(CapyScene.surf);
    expect(
      [for (var i = 0; i < 6; i++) CapyScenes.next(14)],
      [CapyScene.surf, CapyScene.laptop, CapyScene.lamp, CapyScene.ball, CapyScene.mandarin, CapyScene.surf],
    );
    expect(CapyScenes.next(2), CapyScene.sleep);
    expect(CapyScenes.next(23), CapyScene.sleep);
    expect(CapyScenes.next(5), CapyScene.laptop); // ночь круг не сдвигает
  });

  testWidgets('потянул — капибара на сёрфе, пока грузится; пришло — уехала', (t) async {
    phone(t);
    CapyScenes.startAt(CapyScene.surf);
    var calls = 0;
    var done = Completer<void>();
    await t.pumpWidget(
      list(() {
        calls++;
        return done.future;
      }, hour: 14),
    );
    expect(card, findsNothing);

    await t.drag(find.byType(ListView), const Offset(0, 400));
    await settle(t);
    expect(calls, 1);
    expect(card, findsOneWidget);
    expect(find.text('ловлю волну…'), findsNothing); // маленькая, без подписи
    final img = t.widget<CapyImage>(find.descendant(of: card, matching: find.byType(CapyImage)));
    expect(img.pose, CapyPose.surf);
    // карточка целиком на экране, сверху
    final box = t.getRect(card);
    expect(box.top, greaterThanOrEqualTo(0));
    expect(box.height, CapyRefresh.cardHeight);
    // строки съехали вниз — капибара в просвете, а не поверх них
    expect(t.getTopLeft(find.text('строка 0')).dy, greaterThan(box.bottom));

    done.complete();
    await settle(t);
    expect(card, findsNothing);
    expect(t.getTopLeft(find.text('строка 0')).dy, lessThan(CapyRefresh.cardHeight));
    expect(t.takeException(), isNull);

    // следующий раз — следующая сцена
    done = Completer<void>();
    await t.drag(find.byType(ListView), const Offset(0, 400));
    await settle(t);
    final next = t.widget<CapyImage>(find.descendant(of: card, matching: find.byType(CapyImage)));
    expect(next.pose, CapyPose.day); // ноутбук
    expect(calls, 2);
    done.complete();
    await settle(t);
  });

  testWidgets('чуть потянул и отпустил — не обновляет, карточка прячется', (t) async {
    phone(t);
    var calls = 0;
    await t.pumpWidget(
      list(() async {
        calls++;
      }, hour: 14),
    );
    await t.drag(find.byType(ListView), const Offset(0, 40));
    await settle(t);
    expect(calls, 0);
    expect(card, findsNothing);
  });

  testWidgets('ночью — спит, но обновляет', (t) async {
    phone(t);
    final done = Completer<void>();
    await t.pumpWidget(list(() => done.future, hour: 2));
    await t.drag(find.byType(ListView), const Offset(0, 400));
    await settle(t);
    final img = t.widget<CapyImage>(find.descendant(of: card, matching: find.byType(CapyImage)));
    expect(img.pose, CapyPose.night);
    done.complete();
    await settle(t);
  });

  testWidgets('первая загрузка — капибара с подписью вместо крутилки, потом данные', (t) async {
    phone(t);
    CapyScenes.startAt(CapyScene.surf);
    final done = Completer<String>();
    await t.pumpWidget(
      host(
        Loader<String>(
          load: () => done.future,
          builder: (context, v, _) => ListView(children: [Text(v)]),
        ),
      ),
    );
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(CapyLoading), findsOneWidget);
    expect(find.text('ловлю волну…'), findsOneWidget);
    done.complete('пары');
    await settle(t);
    expect(find.byType(CapyLoading), findsNothing);
    expect(find.text('пары'), findsOneWidget);
  });

  testWidgets('ночью при загрузке — спит', (t) async {
    await t.pumpWidget(host(const CapyLoading(hour: 1)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('сплю, но обновляю…'), findsOneWidget);
  });

  for (final p in [Palette.depth, Palette.notebook]) {
    testWidgets('каждая сцена рисуется без ошибок (${p.dark ? 'тёмная' : 'светлая'})', (t) async {
      for (final scene in CapyScene.values) {
        await t.pumpWidget(
          host(
            Center(
              child: SizedBox(
                width: 220,
                height: 84,
                child: CapySceneView(key: ValueKey(scene), scene: scene),
              ),
            ),
            p: p,
          ),
        );
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 230));
        }
        expect(t.takeException(), isNull, reason: '$scene');
        expect(find.byType(CapyImage), findsOneWidget, reason: '$scene');
      }
    });
  }
}
