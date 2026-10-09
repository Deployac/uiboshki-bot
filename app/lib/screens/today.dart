// «Сегодня» — живой день: что идёт сейчас и сколько осталось, что дальше,
// весь день списком и что горит по срокам. Время тикает раз в минуту.
import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/capy.dart';
import '../widgets/common.dart';
import 'lesson.dart';

class TodayData {
  final List<Lesson> lessons;
  final Lesson? tomorrowFirst;
  final List<Deadline> soon;
  final String weather;
  TodayData(this.lessons, this.tomorrowFirst, this.soon, this.weather);
}

const _ordinal = ['первая', 'вторая', 'третья', 'четвёртая', 'пятая', 'шестая', 'седьмая', 'восьмая'];

class TodayScreen extends StatefulWidget {
  final Api api;
  final VoidCallback? onUnauthorized;
  const TodayScreen({super.key, required this.api, this.onUnauthorized});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<TodayData> _load() async {
    final j = await widget.api.get('/today');
    final lessons = [for (final l in j['lessons'] as List) Lesson.fromJson(l)];
    final tf = j['tomorrow_first'];
    final soon = [
      for (final d in (j['deadlines']?['soon'] as List? ?? []))
        if ((d['days'] ?? 0) >= 0) Deadline.fromJson(d),
    ];
    return TodayData(lessons, tf == null ? null : Lesson.fromJson(tf), soon, j['weather'] ?? '');
  }

  @override
  Widget build(BuildContext context) => Loader<TodayData>(
    load: _load,
    onUnauthorized: widget.onUnauthorized,
    builder: (context, d, _) => _TodayView(d, widget.api),
  );
}

class _TodayView extends StatelessWidget {
  final TodayData d;
  final Api api;
  const _TodayView(this.d, this.api);

  @override
  Widget build(BuildContext context) {
    final t = now();
    final lessons = d.lessons;
    Lesson? current, next;
    for (final l in lessons) {
      if (l.startAt == null || l.endAt == null) continue;
      if (!t.isBefore(l.startAt!) && t.isBefore(l.endAt!)) current = l;
      if (next == null && t.isBefore(l.startAt!)) next = l;
    }
    final String title;
    if (lessons.isEmpty) {
      title = 'Сегодня пар нет';
    } else if (current != null) {
      final n = lessons.indexOf(current);
      title = 'Идёт ${n < _ordinal.length ? _ordinal[n] : '${n + 1}-я'} пара';
    } else if (next != null) {
      title = next == lessons.first ? 'Скоро первая пара' : 'Перемена';
    } else {
      title = 'Пары закончились';
    }
    final hero = current ?? (next == lessons.firstOrNull ? next : null);
    final after = current != null ? next : (hero == null ? next : _after(lessons, hero));

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        ScreenTitle(
          eyebrow: dayTitle(t),
          title: title,
          trailing: CapyBadge(hour: t.hour),
        ),
        if (hero != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: _Hero(lesson: hero, live: hero == current, onTap: () => openLesson(context, api, hero)),
          ),
        if (after != null) ...[
          const SizedBox(height: Space.m),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: _Next(lesson: after, prev: current, onTap: () => openLesson(context, api, after)),
          ),
        ],
        if (lessons.isEmpty)
          Notice(
            title: 'Отдыхай',
            text: d.tomorrowFirst == null
                ? 'Завтра тоже свободно.'
                : 'Завтра первая — ${d.tomorrowFirst!.start}, ${d.tomorrowFirst!.title}.',
            pose: CapyPose.joy,
          ),
        if (lessons.isNotEmpty) ...[
          const Section('Весь день'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: LessonList(lessons: lessons, at: t, onTap: (l) => openLesson(context, api, l)),
          ),
        ],
        if (d.soon.isNotEmpty) ...[
          const Section('Горит'),
          for (final x in d.soon)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: _SoonRow(x, at: t),
            ),
        ],
        if (d.weather.isNotEmpty) ...[
          const Section('Погода'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            child: Text(d.weather, style: AppStyle.of(context).body(14, color: AppStyle.of(context).p.muted)),
          ),
        ],
      ],
    );
  }

  Lesson? _after(List<Lesson> all, Lesson l) {
    final i = all.indexOf(l);
    return i >= 0 && i + 1 < all.length ? all[i + 1] : null;
  }
}

/// Большая карточка: пара сейчас (минут до конца и полоска) или первая пара дня.
class _Hero extends StatelessWidget {
  final Lesson lesson;
  final bool live;
  final VoidCallback? onTap;
  const _Hero({required this.lesson, required this.live, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final c = subjectColor(lesson.title);
    final t = now();
    final total = lesson.endAt!.difference(lesson.startAt!).inSeconds;
    final passed = t.difference(lesson.startAt!).inSeconds.clamp(0, total);
    final minutes = live ? lesson.endAt!.difference(t).inMinutes + 1 : lesson.startAt!.difference(t).inMinutes + 1;
    return Tile(
      onTap: onTap,
      radius: Radii.card,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          c.withValues(alpha: p.dark ? 0.42 : 0.28),
          p.cardSolid.withValues(alpha: p.dark ? 0.6 : 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(live ? 'Сейчас · ${lesson.kind}' : 'Первая · ${lesson.start}', style: s.eyebrow(color: c)),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          FitWords(lesson.title, style: s.title(21)),
          const SizedBox(height: Space.m),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${minutes > 0 ? minutes : 0}', style: s.number(56, color: live ? c : p.text)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${plural(minutes, 'минута', 'минуты', 'минут')}\n${live ? 'до конца' : 'до начала'}',
                    style: s.body(13, color: p.muted),
                  ),
                ),
              ],
            ),
          ),
          if (live) ...[
            const SizedBox(height: Space.m),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : passed / total,
                minHeight: 5,
                color: c,
                backgroundColor: p.line,
              ),
            ),
          ],
          const SizedBox(height: Space.m),
          Wrap(
            spacing: Space.l,
            runSpacing: 4,
            children: [
              if (lesson.room.isNotEmpty) _Meta(Icons.place_outlined, lesson.room),
              if (lesson.teacher.isNotEmpty) _Meta(Icons.person_outline_rounded, lesson.teacher),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: s.p.muted),
        const SizedBox(width: 4),
        // длинное ФИО или аудитория переносится, а не вылезает за карточку
        Flexible(
          child: Text(text, style: s.body(13, color: s.p.muted)),
        ),
      ],
    );
  }
}

/// «Дальше · 12:40» и подсказка, если следующая пара в другом корпусе.
class _Next extends StatelessWidget {
  final Lesson lesson;
  final Lesson? prev;
  final VoidCallback? onTap;
  const _Next({required this.lesson, this.prev, this.onTap});

  static String campus(String room) {
    final m = RegExp(r'\(([^)]+)\)').firstMatch(room);
    return m?.group(1) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final from = prev == null ? '' : campus(prev!.room);
    final to = campus(lesson.room);
    final moving = from.isNotEmpty && to.isNotEmpty && from != to;
    final gap = prev?.endAt != null && lesson.startAt != null ? lesson.startAt!.difference(prev!.endAt!).inMinutes : 0;
    return Tile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Дальше · ${lesson.start}', style: s.eyebrow()),
          const SizedBox(height: 6),
          Text(lesson.title, style: s.body(17, weight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(lesson.place, style: s.body(13, color: p.muted)),
          if (moving) ...[
            const SizedBox(height: Space.s),
            Row(
              children: [
                Icon(Icons.directions_walk_rounded, size: 16, color: p.warn),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Другой корпус — $to, на переход $gap мин',
                    style: s.body(13, weight: FontWeight.w600, color: p.warn),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Пары списком: время, полоска цвета предмета, название и место.
/// Прошедшие — бледнее, идущая — подписана.
class LessonList extends StatelessWidget {
  final List<Lesson> lessons;
  final DateTime at;

  /// Нажал пару — её экран («Пара»); null — список только для чтения.
  final ValueChanged<Lesson>? onTap;

  /// Расписание преподавателя или аудитории: под парой — чьи это пары.
  final bool showGroups;
  const LessonList({super.key, required this.lessons, required this.at, this.onTap, this.showGroups = false});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Tile(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < lessons.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: p.line),
            Builder(
              builder: (context) {
                final l = lessons[i];
                final past = l.endAt != null && !at.isBefore(l.endAt!);
                final live = l.startAt != null && !past && !at.isBefore(l.startAt!);
                final row = Opacity(
                  opacity: past ? 0.45 : 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            // «09:00» не рвётся на «09:0/0» при крупном системном шрифте
                            width: MediaQuery.textScalerOf(context).scale(50),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.start, style: s.body(15, weight: FontWeight.w600)),
                                Text(l.end, style: s.body(12, color: p.muted)),
                              ],
                            ),
                          ),
                          Container(
                            width: 3,
                            margin: const EdgeInsets.only(right: Space.m),
                            decoration: BoxDecoration(
                              color: subjectColor(l.title),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.title, style: s.body(15, weight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    l.place,
                                    if (showGroups && l.groups.isNotEmpty) l.groups,
                                    if (live) 'идёт',
                                  ].join(' · '),
                                  style: s.body(13, color: live ? subjectColor(l.title) : p.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                if (onTap == null) return row;
                return InkWell(
                  onTap: () {
                    tick();
                    onTap!(l);
                  },
                  child: row,
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SoonRow extends StatelessWidget {
  final Deadline d;
  final DateTime at;
  const _SoonRow(this.d, {required this.at});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final left = d.due.difference(at);
    final hot = left.inHours < 24;
    return Tile(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_outlined, size: 18, color: hot ? s.p.danger : s.p.warn),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(d.subject, style: s.body(15, weight: FontWeight.w600)),
          ),
          const SizedBox(width: Space.s),
          Text(
            leftText(left),
            style: s.body(13, weight: FontWeight.w600, color: hot ? s.p.danger : s.p.muted),
          ),
        ],
      ),
    );
  }
}
