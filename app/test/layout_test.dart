// Вёрстка всех экранов: маленький телефон (320×568) с крупным системным
// шрифтом и большой (430×932), обе темы и оба шрифта, «чёлка» и полоска
// «Домой». Любое переполнение (RenderFlex overflowed) или исключение
// роняет тест; заголовок не под часами, капсула не под полоской, конец
// списка не прячется под капсулой, клавиатура не закрывает поле помощника.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uiboshki/api/api.dart';
import 'package:uiboshki/api/models.dart';
import 'package:uiboshki/main.dart';
import 'package:uiboshki/screens/chat.dart';
import 'package:uiboshki/screens/deadline_edit.dart';
import 'package:uiboshki/screens/files.dart';
import 'package:uiboshki/screens/group_pick.dart';
import 'package:uiboshki/screens/homework.dart';
import 'package:uiboshki/screens/lesson.dart';
import 'package:uiboshki/screens/login.dart';
import 'package:uiboshki/screens/notify.dart';
import 'package:uiboshki/screens/sdo_connect.dart';
import 'package:uiboshki/screens/search.dart';
import 'package:uiboshki/screens/security.dart';
import 'package:uiboshki/screens/study.dart';
import 'package:uiboshki/screens/submit.dart';
import 'package:uiboshki/screens/task.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/widgets/capsule_tabbar.dart';
import 'package:uiboshki/widgets/common.dart';

import 'fake_api.dart';
import 'util.dart';

/// Самые длинные настоящие строки: предмет, ФИО, аудитория.
const longSubject = 'Анализ и диагностика финансово-хозяйственной деятельности предприятия';
const longTeacher = 'Константинопольская-Задунайская Е. В.';
const longRoom = 'ИВЦ-126 (В-78)';

class Device {
  final String name;
  final Size size;
  final double scale;
  final EdgeInsets pad;
  const Device(this.name, this.size, this.scale, this.pad);
}

const _notch = EdgeInsets.only(top: 59, bottom: 34);
const devices = [
  Device('320×568 ×1.3', Size(320, 568), 1.3, _notch),
  Device('375×667', Size(375, 667), 1.0, EdgeInsets.only(top: 20)),
  Device('430×932', Size(430, 932), 1.0, _notch),
];

void useDevice(WidgetTester t, Device d, {double keyboard = 0}) {
  const dpr = 2.0;
  t.view.devicePixelRatio = dpr;
  t.view.physicalSize = d.size * dpr;
  t.view.padding = FakeViewPadding(top: d.pad.top * dpr, bottom: d.pad.bottom * dpr);
  t.view.viewPadding = FakeViewPadding(top: d.pad.top * dpr, bottom: d.pad.bottom * dpr);
  if (keyboard > 0) t.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
  t.platformDispatcher.textScaleFactorTestValue = d.scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Настоящие шрифты приложения: у тестового «квадратного» другая ширина.
Future<void> loadFonts() async {
  Future<void> one(String family, String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await l.load();
  }

  await one('Onest', 'assets/fonts/Onest.ttf');
  await one('SourceSerif', 'assets/fonts/SourceSerif4.ttf');
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/home/user/sdk/flutter';
  await one('MaterialIcons', '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

/// Ответы стенда, где ФИО и аудитории — самые длинные.
Api longApi({List<String>? requests, Map<String, Object?> extra = const {}}) {
  final raw = jsonEncode(demoFixtures())
      .replaceAll('Бурлаков В. В.', longTeacher)
      .replaceAll('Стебунова О. И.', longTeacher)
      .replaceAll('А-223 (В-78)', longRoom);
  final fx = Map<String, Object?>.from(jsonDecode(raw));
  return fakeApi(
    requests: requests,
    overrides: {...fx, ..._aroundNow(fx), 'GET /api/target/2/77': targetFixture, ...extra},
  );
}

String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Запись стенда — на неделю 5–11 октября; тест идёт «сейчас»: неделя
/// переезжает на текущую, а на «Сегодня» идёт вторая пара (длинное
/// название и ФИО) — так видны большая карточка и «Дальше».
Map<String, Object?> _aroundNow(Map<String, Object?> fx) {
  final t = DateTime.now();
  final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
  String move(Object? v) {
    var s = jsonEncode(v);
    for (var i = 0; i < 7; i++) {
      s = s.replaceAll(_d(DateTime(2026, 10, 5 + i)), _d(monday.add(Duration(days: i))));
    }
    return s;
  }

  final today = Map<String, dynamic>.from(fx['GET /api/today'] as Map);
  final lessons = [for (final l in today['lessons'] as List) Map<String, dynamic>.from(l)];
  for (var i = 0; i < lessons.length; i++) {
    final start = t.add(Duration(minutes: (i - 1) * 100 - 10));
    final end = start.add(const Duration(minutes: 90));
    lessons[i]
      ..['start'] = _hm(start)
      ..['end'] = _hm(end)
      ..['start_iso'] = start.toIso8601String()
      ..['end_iso'] = end.toIso8601String();
  }
  today['lessons'] = lessons;
  return {
    'GET /api/today': today,
    'GET /api/week?start=${_d(monday)}': jsonDecode(move(fx['GET /api/week?start=2026-10-05'])),
    for (var i = 0; i < 7; i++)
      'GET /api/day?date=${_d(monday.add(Duration(days: i)))}': jsonDecode(
        move(fx['GET /api/day?date=${_d(DateTime(2026, 10, 5 + i))}']),
      ),
  };
}

Widget host(Palette p, FontChoice f, Widget child) => AppStyle(
  p: p,
  font: f,
  child: MaterialApp(theme: materialTheme(p), home: child),
);

Size _screen(WidgetTester t) => t.view.physicalSize / t.view.devicePixelRatio;

/// Прокрутить каждый список до конца и обратно — ленивые строки тоже
/// строятся и проверяются на переполнение.
Future<void> scrollThrough(WidgetTester t, {bool tabbar = false}) async {
  noClippedText(t);
  noBrokenWords(t);
  for (final st in t.stateList<ScrollableState>(find.byType(Scrollable)).toList()) {
    if (!st.mounted) continue;
    final pos = st.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) continue;
    var guard = 0;
    while (st.mounted && pos.pixels < pos.maxScrollExtent - 0.5 && guard++ < 60) {
      pos.jumpTo(math.min(pos.pixels + pos.viewportDimension * 0.7, pos.maxScrollExtent));
      await t.pump(const Duration(milliseconds: 50));
      noClippedText(t);
      noBrokenWords(t);
    }
    if (!st.mounted) continue;
    if (tabbar && pos.axis == Axis.vertical) _endAboveTabbar(t, st);
    pos.jumpTo(0);
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Строка, обрезанная без многоточия (в чипе, в одну строку), — текст
/// пропал молча, без ошибки переполнения. Многоточие — осознанный выбор.
void noClippedText(WidgetTester t) {
  for (final e in find.byType(RichText).evaluate()) {
    final rp = e.renderObject;
    if (rp is! RenderParagraph || !rp.hasSize || rp.size.width == 0) continue;
    if (rp.overflow == TextOverflow.ellipsis || rp.softWrap && rp.maxLines == null) continue;
    final need = rp.getMaxIntrinsicWidth(double.infinity);
    if (rp.maxLines != null && rp.maxLines! > 1) continue;
    expect(need, lessThanOrEqualTo(rp.size.width + 1), reason: 'обрезано без многоточия: «${rp.text.toPlainText()}»');
  }
}

/// Слово, разорванное посередине («09:0/0», «Недел/я»): само слово шире
/// строки, где стоит. Переносы по дефису и пробелу — норма.
void noBrokenWords(WidgetTester t) {
  // С крупным системным шрифтом на 320 px сверхдлинное слово («Константинопольская-…»)
  // иначе не влезет — там проверяем только переполнения, не переносы.
  if (t.platformDispatcher.textScaleFactor > 1) return;
  for (final e in find.byType(RichText).evaluate()) {
    final rp = e.renderObject;
    if (rp is! RenderParagraph || !rp.hasSize || rp.size.width == 0 || !rp.softWrap) continue;
    if (rp.maxLines == 1) continue;
    final style = _firstStyle(rp.text);
    for (final w in rp.text.toPlainText().split(RegExp(r'[\s\-‐–—/]+'))) {
      if (w.length < 2) continue;
      final tp = TextPainter(
        text: TextSpan(text: w, style: style),
        textDirection: TextDirection.ltr,
        textScaler: rp.textScaler,
      )..layout();
      final width = tp.width;
      tp.dispose();
      expect(width, lessThanOrEqualTo(rp.size.width + 1), reason: 'слово разорвано: «$w» в «${rp.text.toPlainText()}»');
    }
  }
}

TextStyle? _firstStyle(InlineSpan s) {
  TextStyle? found;
  TextStyle? merged;
  s.visitChildren((c) {
    if (c is TextSpan && c.text != null && c.text!.trim().isNotEmpty) {
      found = c.style;
      return false;
    }
    return true;
  });
  merged = s.style?.merge(found) ?? found;
  return merged;
}

/// В конце списка последняя строка видна над капсулой, а не под ней.
void _endAboveTabbar(WidgetTester t, ScrollableState st) {
  final bar = find.byType(CapsuleTabBar);
  if (bar.evaluate().isEmpty) return;
  // верх самой капсулы (без отступа SafeArea снизу)
  final pill = find.descendant(of: bar, matching: find.byType(ClipRRect)).first;
  final top = t.getRect(pill).top;
  final view = t.getRect(find.byWidget(st.widget));
  var bottom = 0.0;
  for (final e in find.descendant(of: find.byWidget(st.widget), matching: find.byType(RichText)).evaluate()) {
    final r = t.getRect(find.byElementPredicate((x) => x == e));
    if (r.top < view.bottom && r.bottom > bottom) bottom = r.bottom;
  }
  expect(bottom, lessThanOrEqualTo(top + 0.5), reason: 'конец списка под капсулой');
}

/// Наверху экрана ни одна видимая надпись не залезает под часы и «чёлку»
/// (то, что уехало вверх в прокрутке и обрезано списком, — не в счёт).
void _belowNotch(WidgetTester t, Device d) {
  for (final e in find.byType(RichText).evaluate()) {
    var r = t.getRect(find.byElementPredicate((x) => x == e));
    final sc = Scrollable.maybeOf(e);
    if (sc != null) r = r.intersect(t.getRect(find.byWidget(sc.widget)));
    if (r.height <= 0 || r.width <= 0 || r.bottom <= 0) continue;
    expect(
      r.top,
      greaterThanOrEqualTo(d.pad.top - 0.5),
      reason: 'надпись под часами: ${(e.widget as RichText).text.toPlainText()}',
    );
  }
}

/// Меню-капсула — над полоской «Домой».
void _tabbarAboveHome(WidgetTester t, Device d) {
  final pill = find.descendant(of: find.byType(CapsuleTabBar), matching: find.byType(ClipRRect)).first;
  expect(
    t.getRect(pill).bottom,
    lessThanOrEqualTo(_screen(t).height - d.pad.bottom + 0.5),
    reason: 'капсула под полоской',
  );
}

typedef Screen = Widget Function(Api api);

/// Расписание преподавателя с самыми длинными строками.
final targetFixture = {
  'type': 2,
  'id': 77,
  'title': longTeacher,
  'pinned': false,
  'today': '2026-10-08',
  'stale': null,
  'weeks': [
    {
      'monday': '2026-10-05',
      'week': 6,
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'date': '2026-10-${(5 + i).toString().padLeft(2, '0')}',
            'lessons': [
              if (i < 5)
                {
                  'start': '10:40',
                  'end': '12:10',
                  'title': longSubject,
                  'kind': 'практика',
                  'room': longRoom,
                  'groups': 'УИБО-01-24, УИБО-02-24, УИБО-03-24',
                },
            ],
          },
      ],
    },
  ],
};

/// Все экраны, кроме вкладок (их открывает сама оболочка).
Map<String, Screen> allScreens() {
  final fx = demoFixtures();
  Course course(int id) => Course.fromJson(Map<String, dynamic>.from(fx['GET /api/sdo/grades/$id']));
  final files = [
    for (final f in fx['GET /api/files']['items'] as List) FileItem.fromJson(Map<String, dynamic>.from(f)),
  ];
  final work = Map<String, dynamic>.from((fx['GET /api/sdo/grades/18672']['works'] as List).first);
  final dl = Map<String, dynamic>.from((fx['GET /api/deadlines?include_done=true']['items'] as List).first);
  const lesson = Lesson(
    start: '10:40',
    end: '12:10',
    title: longSubject,
    kind: 'практика',
    room: longRoom,
    teacher: longTeacher,
    status: '',
    groups: 'УИБО-01-24, УИБО-02-24, УИБО-03-24, УИБО-04-24, УИБО-05-24',
  );

  return <String, Screen>{
    'вход': (api) => LoginScreen(api: api, onDone: () {}),
    'поиск': (api) => SearchScreen(api: api),
    'расписание преподавателя': (api) => TargetScreen(api: api, type: 2, id: 77, title: longTeacher),
    'файлы': (api) => FilesScreen(api: api),
    'файлы предмета': (api) => SubjectFilesScreen(api: api, subject: longSubject, files: files),
    'помощник': (api) => ChatScreen(api: api),
    'ДЗ': (api) => HomeworkScreen(api: api),
    'заметки': (api) => NotesScreen(api: api),
    'вход в СДО': (api) => SdoConnectScreen(api: api),
    'группа': (api) => GroupPickScreen(api: api),
    'уведомления': (api) => NotifyScreen(api: api),
    'безопасность': (api) => SecurityScreen(api: api, onLogout: () {}),
    for (final id in [18672, 18673, 18674, 18675, 18676, 18677])
      'предмет $id': (api) => CourseScreen(api: api, course: course(id)),
    'задание': (api) => TaskScreen(api: api, work: work, course: longSubject),
    'пара': (api) => LessonScreen(api: api, lesson: lesson),
    'сдать': (api) => Scaffold(
      body: SubmitSheet(api: api, title: longSubject, deadlineId: 7),
    ),
    'новый срок': (api) => Scaffold(body: DeadlineEditSheet(api: api)),
    'изменить срок': (api) => Scaffold(
      body: DeadlineEditSheet(api: api, d: Deadline.fromJson(dl), x: DlExtra.fromJson(dl)),
    ),
    'напомнить': (api) => Scaffold(
      body: RemindSheet(
        api: api,
        d: Deadline.fromJson(dl),
        reminders: const [(at: '2026-10-14T23:59', label: 'за день, 14 октября 23:59')],
        due: 'четверг, 15 октября, 23:59',
      ),
    ),
  };
}

void main() {
  setUpAll(loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({'uib_toured': true}));

  for (final d in devices) {
    for (final p in [Palette.depth, Palette.notebook]) {
      for (final f in FontChoice.values) {
        final tag = '${d.name} · ${p.dark ? 'тёмная' : 'светлая'} · ${f.name}';

        testWidgets('вкладки: $tag', (t) async {
          useDevice(t, d);
          t.platformDispatcher.platformBrightnessTestValue = p.dark ? Brightness.dark : Brightness.light;
          addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
          await t.pumpWidget(UiboApp(api: longApi(), font: f));
          await settle(t);
          for (var i = 0; i < 5; i++) {
            await t.tap(find.descendant(of: find.byType(CapsuleTabBar), matching: find.byType(GestureDetector)).at(i));
            await settle(t);
            _belowNotch(t, d);
            _tabbarAboveHome(t, d);
            await scrollThrough(t, tabbar: true);
          }
        });

        for (final e in allScreens().entries) {
          testWidgets('${e.key}: $tag', (t) async {
            useDevice(t, d);
            await t.pumpWidget(host(p, f, e.value(longApi())));
            await settle(t);
            _belowNotch(t, d);
            await scrollThrough(t);
          });
        }
      }
    }
  }

  // Ответ помощника: «по какому предмету?» с длинными названиями, файлы и источники.
  for (final d in devices) {
    for (final answer in [
      {
        'content': 'По какому предмету?',
        'choose': [longSubject, 'Анализ данных'],
      },
      {
        ...Map<String, Object?>.from(demoFixtures()['POST /api/chat']),
        'files': [
          {'id': 2, 'title': 'Лекция 2. Требования и стейкхолдеры · $longSubject', 'subject': longSubject},
        ],
      },
    ]) {
      testWidgets('помощник отвечает: ${d.name} · ${answer['choose'] != null ? 'выбор' : 'ответ'}', (t) async {
        useDevice(t, d);
        await t.pumpWidget(
          host(Palette.notebook, FontChoice.book, ChatScreen(api: longApi(extra: {'POST /api/chat': answer}))),
        );
        await settle(t);
        await t.enterText(find.byType(TextField), 'Объясни 3 лекцию');
        await t.tap(find.byTooltip('Отправить'));
        await settle(t);
        await scrollThrough(t);
      });
    }
  }

  // Клавиатура открыта — поле вопроса и кнопка над ней, а не под ней.
  for (final d in devices) {
    testWidgets('помощник с клавиатурой: ${d.name}', (t) async {
      useDevice(t, d, keyboard: 300);
      await t.pumpWidget(host(Palette.depth, FontChoice.book, ChatScreen(api: longApi())));
      await settle(t);
      final field = t.getRect(find.byType(TextField));
      expect(field.bottom, lessThanOrEqualTo(_screen(t).height - 300 + 0.5));
      expect(field.top, greaterThan(d.pad.top));
    });
  }

  // Без сети — баннер наверху, ниже часов, не налезает на заголовок.
  for (final d in devices) {
    testWidgets('баннер «без сети»: ${d.name}', (t) async {
      useDevice(t, d);
      final api = longApi();
      await t.pumpWidget(UiboApp(api: api));
      await settle(t);
      api.offlineSince.value = DateTime(2026, 10, 7, 10, 7);
      await settle(t);
      _belowNotch(t, d);
      final banner = t.getRect(find.textContaining('Без сети'));
      final title = t.getRect(find.byType(ScreenTitle).first);
      expect(banner.bottom, lessThanOrEqualTo(title.top));
    });
  }

  // Знакомство «Что где» на маленьком экране с крупным шрифтом.
  testWidgets('знакомство на маленьком экране', (t) async {
    SharedPreferences.setMockInitialValues({});
    useDevice(t, devices.first);
    await t.pumpWidget(UiboApp(api: longApi()));
    await settle(t);
    expect(find.text('Что где'), findsOneWidget);
    await scrollThrough(t);
    await t.ensureVisible(find.text('Понятно'));
    await settle(t);
    final ok = t.getRect(find.text('Понятно'));
    expect(ok.bottom, lessThanOrEqualTo(_screen(t).height - devices.first.pad.bottom + 0.5));
  });
}
