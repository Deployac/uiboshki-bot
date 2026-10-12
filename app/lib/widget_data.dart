// Виджеты рабочего стола (второй круг дизайна, Никита 12.10: А, В, Г, Д).
// Приложение кладёт компактный снимок — пары сегодня и завтра и горящий срок —
// в общее с виджетом хранилище (Android — SharedPreferences, iPhone — файл в
// App Group); «через 12 мин» и «идёт · ещё 23’» виджет считает сам от текущего
// времени, день берёт по дате (снимок может быть и вчерашним).
// Новый дизайн выключен сервером (features.design2) — снимок не пишется и
// стирается, виджет просит открыть Капибару. Виджет человек добавляет сам.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api.dart';
import 'api/models.dart';
import 'screens/today.dart' show TodayData, splitRoom;
import 'theme/look.dart';
import 'widgets/common.dart' show now;

/// Версия формата снимка: виджеты на телефоне читают её и не ломаются на новой.
const widgetSnapshotVersion = 1;

const _weekdaysCaps = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
const _monthsCaps = ['ЯНВ', 'ФЕВ', 'МАР', 'АПР', 'МАЯ', 'ИЮН', 'ИЮЛ', 'АВГ', 'СЕН', 'ОКТ', 'НОЯ', 'ДЕК'];

/// Момент «дата + ЧЧ:ММ» по Москве — когда у пары нет start_iso (старый сервер).
DateTime? mskAt(String date, String hm) => hm.isEmpty ? null : DateTime.tryParse('${date}T$hm:00+03:00');

/// Следующий день после «2026-10-08».
String nextDate(String date) {
  final d = DateTime.parse(date);
  return iso(DateTime(d.year, d.month, d.day + 1));
}

/// Шапка большого виджета: «ЧТ, 8 ОКТ · 5 ПАР»; известна только первая
/// пара дня — без счёта.
String widgetDayHeader(String date, int count, {bool partial = false}) {
  final d = DateTime.tryParse(date);
  if (d == null) return '';
  final head = '${_weekdaysCaps[d.weekday - 1]}, ${d.day} ${_monthsCaps[d.month - 1]}';
  if (partial) return head;
  if (count == 0) return '$head · ПАР НЕТ';
  return '$head · $count ${plural(count, 'ПАРА', 'ПАРЫ', 'ПАР')}';
}

/// Пара для виджета: время строкой и моментами (мс), название, кабинет без корпуса.
Map<String, Object?> widgetLesson(Lesson l, String date) {
  final s = l.startAt ?? mskAt(date, l.start);
  final e = l.endAt ?? mskAt(date, l.end);
  return {
    's': l.start,
    'e': l.end,
    'sa': s?.millisecondsSinceEpoch ?? 0,
    'ea': e?.millisecondsSinceEpoch ?? 0,
    't': l.title,
    'r': splitRoom(l.room).code,
    'k': l.kind,
  };
}

/// День для виджета; [partial] — из дня известна только первая пара.
Map<String, Object?> widgetDay(String date, List<Lesson> lessons, {bool partial = false}) {
  final list = [
    for (final l in lessons)
      if (!l.cancelled) widgetLesson(l, date),
  ];
  return {'d': date, 'h': widgetDayHeader(date, list.length, partial: partial), 'part': partial, 'l': list};
}

/// Горящий срок: ближайший несданный, ещё не прошедший и не дальше трёх суток.
/// Название — до « · » («Практика 2 · Анализ данных (Экз)» → «Практика 2»).
Map<String, Object?>? hotDeadline(Iterable<Deadline> list, DateTime at) {
  Deadline? best;
  DateTime? bestDue;
  for (final d in list) {
    if (d.done) continue;
    final due = mskAt(d.dueDate, d.dueTime.isEmpty ? '23:59' : d.dueTime);
    if (due == null || !due.isAfter(at) || due.difference(at) > const Duration(days: 3)) continue;
    if (bestDue == null || due.isBefore(bestDue)) {
      best = d;
      bestDue = due;
    }
  }
  if (best == null) return null;
  return {'t': best.subject.split(' · ').first.trim(), 'due': bestDue!.millisecondsSinceEpoch};
}

/// Снимок для виджетов из «Сегодня»: сегодня целиком, завтра — целиком, если
/// догрузили [tomorrow], иначе только первая пара (её /today отдаёт всегда).
Map<String, Object?> widgetSnapshot({
  required DateTime at,
  required String date,
  required TodayData data,
  List<Lesson>? tomorrow,
  Map<String, Object?>? deadline,
}) {
  final next = nextDate(date);
  final first = data.tomorrowFirst;
  return {
    'v': widgetSnapshotVersion,
    'at': at.millisecondsSinceEpoch,
    'days': [
      widgetDay(date, data.lessons),
      if (tomorrow != null)
        widgetDay(next, tomorrow)
      else if (first != null)
        widgetDay(next, [first], partial: true)
      else
        widgetDay(next, const []),
    ],
    'dl': deadline,
  };
}

/// Куда уходит снимок. На телефоне — канал к Android/iPhone, тесты подменяют.
abstract class WidgetSink {
  Future<void> save(String json);
  Future<void> clear();

  /// Сколько виджетов Капибары стоит на экранах (0 — не знаем или нет).
  Future<int> installed();
}

class _ChannelSink implements WidgetSink {
  static const _ch = MethodChannel('ru.uiboshki.app/widgets');

  @override
  Future<void> save(String json) => _ch.invokeMethod<void>('save', {'json': json});

  @override
  Future<void> clear() => _ch.invokeMethod<void>('clear');

  @override
  Future<int> installed() async => await _ch.invokeMethod<int>('installed') ?? 0;
}

class HomeWidgets {
  /// null — виджетов на платформе нет (веб, компьютер).
  static WidgetSink? sink =
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)
      ? _ChannelSink()
      : null;

  /// Последние пары и горящий срок: «Сдать» обновляет только срок.
  static List<Object?>? _days;
  static Map<String, Object?>? _deadline;

  static Future<bool> _enabled() async => design2FromPrefs(await SharedPreferences.getInstance());

  /// После загрузки «Сегодня» (день [date] — как его назвал сервер).
  static Future<void> fromToday(Api api, String date, TodayData data) async {
    final sink = HomeWidgets.sink;
    if (sink == null) return;
    try {
      if (!await _enabled()) return await clear();
      final at = now();
      List<Lesson>? tomorrow;
      // завтра целиком — лишний запрос, только если виджет правда стоит
      if (data.tomorrowFirst != null && await _installed(sink) > 0) {
        try {
          final j = await api.get('/day?date=${nextDate(date)}');
          if (j is Map && j['lessons'] is List) {
            tomorrow = [for (final l in j['lessons'] as List) Lesson.fromJson(Map<String, dynamic>.from(l))];
          }
        } catch (_) {}
      }
      _deadline = hotDeadline(data.soon, at);
      final snap = widgetSnapshot(at: at, date: date, data: data, tomorrow: tomorrow, deadline: _deadline);
      _days = snap['days'] as List<Object?>;
      // пока ждали сеть, сервер мог выключить новый дизайн
      if (!await _enabled()) return await clear();
      await sink.save(jsonEncode(snap));
    } catch (_) {
      // виджет — не главное: ошибка канала экран не трогает
    }
  }

  /// После загрузки «Сдать»: горящий срок по полному списку.
  static Future<void> fromDeadlines(List<Deadline> list) async {
    final sink = HomeWidgets.sink;
    if (sink == null) return;
    try {
      if (!await _enabled()) return await clear();
      final at = now();
      _deadline = hotDeadline(list, at);
      final days = _days;
      if (days == null) return; // пар ещё не знаем — снимок запишет «Сегодня»
      await sink.save(
        jsonEncode({'v': widgetSnapshotVersion, 'at': at.millisecondsSinceEpoch, 'days': days, 'dl': _deadline}),
      );
    } catch (_) {}
  }

  /// Стереть снимок: новый дизайн выключен или вышел из аккаунта.
  static Future<void> clear() async {
    _days = null;
    _deadline = null;
    try {
      await sink?.clear();
    } catch (_) {}
  }

  static Future<int> _installed(WidgetSink sink) async {
    try {
      return await sink.installed();
    } catch (_) {
      return 0;
    }
  }
}
