// «Неделя» — повестка: вся неделя одной лентой, сверху полоса дней с
// точками пар. Нажал день — лента плавно едет к нему; открывается сразу на
// сегодняшнем дне, прошедшие — выше, до них можно долистать (владелец, 09.10,
// 19Б). Соседняя неделя — свайпом вбок или стрелками.
// Сроки сдачи тут не показываем — для них вкладка «Сдать» (владелец, 09.10).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'lesson.dart';
import 'search.dart';
import 'today.dart' show LessonList;

class WeekData {
  final int? number;
  final DateTime monday;
  final Map<String, List<Lesson>> days;
  WeekData(this.number, this.monday, this.days);
}

DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

class WeekScreen extends StatefulWidget {
  final Api api;
  final VoidCallback? onUnauthorized;
  const WeekScreen({super.key, required this.api, this.onUnauthorized});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  int _shift = 0;
  int _dir = 1; // куда уехала неделя: 1 — вперёд, -1 — назад

  void _shiftBy(int k) {
    tick();
    setState(() {
      _dir = k.sign;
      _shift += k;
    });
  }

  Future<WeekData> _load() async {
    final monday = mondayOf(now()).add(Duration(days: 7 * _shift));
    final dates = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final res = await Future.wait([
      widget.api.get('/week?start=${iso(monday)}'),
      for (final d in dates) widget.api.get('/day?date=${iso(d)}'),
    ]);
    final days = <String, List<Lesson>>{};
    for (var i = 0; i < 7; i++) {
      days[iso(dates[i])] = [for (final l in (res[i + 1]['lessons'] as List? ?? [])) Lesson.fromJson(l)];
    }
    return WeekData(res[0]['week'] as int?, monday, days);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    // свайп вбок — соседняя неделя; вертикальную прокрутку ленты не трогает
    behavior: HitTestBehavior.translucent,
    onHorizontalDragEnd: (e) {
      final v = e.primaryVelocity ?? 0;
      if (v.abs() >= 250) _shiftBy(v < 0 ? 1 : -1);
    },
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final incoming = child.key == ValueKey(_shift);
        final from = Offset((incoming ? 0.18 : -0.18) * _dir, 0);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: from, end: Offset.zero).animate(anim),
            child: child,
          ),
        );
      },
      child: Loader<WeekData>(
        key: ValueKey(_shift),
        load: _load,
        onUnauthorized: widget.onUnauthorized,
        builder: (context, d, _) => _WeekView(
          onLesson: (l) => openLesson(context, widget.api, l),
          onSearch: () => openSearch(context, widget.api),
          data: d,
          onShift: _shiftBy,
        ),
      ),
    ),
  );
}

class _WeekView extends StatefulWidget {
  final WeekData data;
  final ValueChanged<int> onShift;
  final ValueChanged<Lesson> onLesson;

  /// Поиск расписания любой группы, преподавателя, аудитории.
  final VoidCallback onSearch;
  const _WeekView({required this.data, required this.onShift, required this.onLesson, required this.onSearch});

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<_WeekView> {
  final _keys = List.generate(7, (_) => GlobalKey());
  final _scroll = ScrollController();

  // День, с которого лента начинается (сегодня): дни до него лежат выше
  // нулевой точки прокрутки — экран открывается прямо на нём, даже если ниже
  // почти пусто (прыжок после первого кадра упирался в конец ленты).
  final _center = const ValueKey('week:center');
  late final int _anchor;
  late int _selected;

  @override
  void initState() {
    super.initState();
    final today = now();
    final i = DateTime(today.year, today.month, today.day).difference(widget.data.monday).inDays;
    _selected = _anchor = i >= 0 && i < 7 ? i : 0;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int i, {bool animate = true}) {
    setState(() => _selected = i);
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: animate ? const Duration(milliseconds: 420) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final d = widget.data;
    final sunday = d.monday.add(const Duration(days: 6));
    final range = d.monday.month == sunday.month
        ? '${d.monday.day}–${sunday.day} ${monthsGen[sunday.month - 1]}'
        : '${d.monday.day} ${monthsGen[d.monday.month - 1]} – ${sunday.day} ${monthsGen[sunday.month - 1]}';
    final t = now();
    final todayIso = iso(t);
    return Column(
      children: [
        ScreenTitle(
          eyebrow: d.number != null ? '${d.number} неделя · $range' : range,
          title: 'Неделя',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Поиск расписания',
                onPressed: () {
                  tick();
                  widget.onSearch();
                },
                icon: Icon(Icons.search_rounded, color: p.muted),
              ),
              IconButton(
                tooltip: 'Прошлая неделя',
                onPressed: () => widget.onShift(-1),
                icon: Icon(Icons.chevron_left_rounded, color: p.muted),
              ),
              IconButton(
                tooltip: 'Следующая неделя',
                onPressed: () => widget.onShift(1),
                icon: Icon(Icons.chevron_right_rounded, color: p.muted),
              ),
            ],
          ),
        ),
        // Полоса дней
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayCell(
                    date: d.monday.add(Duration(days: i)),
                    dots: d.days[iso(d.monday.add(Duration(days: i)))]?.length ?? 0,
                    selected: i == _selected,
                    today: iso(d.monday.add(Duration(days: i))) == todayIso,
                    onTap: () {
                      tick();
                      _go(i);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        Divider(height: 1, color: p.line),
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            center: _center,
            // все семь дней строятся сразу — нажатие на день доезжает и до понедельника
            scrollCacheExtent: const ScrollCacheExtent.pixels(5000),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              for (var i = 0; i < 7; i++)
                SliverToBoxAdapter(
                  key: i == _anchor ? _center : null,
                  child: _DayBlock(
                    key: _keys[i],
                    date: d.monday.add(Duration(days: i)),
                    lessons: d.days[iso(d.monday.add(Duration(days: i)))] ?? const [],
                    today: iso(d.monday.add(Duration(days: i))) == todayIso,
                    at: t,
                    onLesson: widget.onLesson,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 160)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final int dots;
  final bool selected, today;
  final VoidCallback onTap;
  const _DayCell({
    required this.date,
    required this.dots,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final fg = selected ? p.bg : (today ? p.accent : p.text);
    return Semantics(
      button: true,
      selected: selected,
      label: dayTitle(date),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? p.text : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.chip),
          ),
          child: Column(
            children: [
              Text(weekdaysShort[date.weekday - 1], style: s.body(12, color: selected ? p.bg : p.muted)),
              const SizedBox(height: 2),
              Text('${date.day}', style: s.number(21, color: fg)),
              const SizedBox(height: 5),
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var k = 0; k < dots.clamp(0, 5); k++)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: (selected ? p.bg : p.muted).withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayBlock extends StatelessWidget {
  final DateTime date;
  final List<Lesson> lessons;
  final bool today;
  final DateTime at;
  final ValueChanged<Lesson>? onLesson;
  const _DayBlock({
    super.key,
    required this.date,
    required this.lessons,
    required this.today,
    required this.at,
    this.onLesson,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Space.s, bottom: Space.s),
            child: Text(
              today ? '${dayTitle(date)} · сегодня' : dayTitle(date),
              style: s.eyebrow(color: today ? p.text : p.muted),
            ),
          ),
          if (lessons.isEmpty)
            Tile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(today ? 'Сегодня пар нет' : 'Пар нет', style: s.body(17, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('отдыхай', style: s.body(13, color: p.muted)),
                ],
              ),
            )
          else
            LessonList(lessons: lessons, at: at, onTap: onLesson),
        ],
      ),
    );
  }
}
