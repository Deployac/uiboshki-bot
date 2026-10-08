// «Неделя» — повестка: вся неделя одной лентой, сверху полоса дней с
// точками пар. Нажал день — лента плавно едет к нему; по умолчанию выбран
// сегодняшний, даже если пар нет. Сроки сдачи — прямо в дне.
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'lesson.dart';
import 'today.dart' show LessonList;

class WeekData {
  final int? number;
  final DateTime monday;
  final Map<String, List<Lesson>> days;
  final Map<String, List<Deadline>> due;
  WeekData(this.number, this.monday, this.days, this.due);
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

  Future<WeekData> _load() async {
    final monday = mondayOf(now()).add(Duration(days: 7 * _shift));
    final dates = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final res = await Future.wait([
      widget.api.get('/week?start=${iso(monday)}'),
      widget.api.get('/deadlines'),
      for (final d in dates) widget.api.get('/day?date=${iso(d)}'),
    ]);
    final days = <String, List<Lesson>>{};
    for (var i = 0; i < 7; i++) {
      days[iso(dates[i])] = [for (final l in (res[i + 2]['lessons'] as List? ?? [])) Lesson.fromJson(l)];
    }
    final due = <String, List<Deadline>>{};
    for (final x in res[1]['items'] as List) {
      final d = Deadline.fromJson(x);
      if (!d.done && days.containsKey(d.dueDate)) (due[d.dueDate] ??= []).add(d);
    }
    return WeekData(res[0]['week'] as int?, monday, days, due);
  }

  @override
  Widget build(BuildContext context) => Loader<WeekData>(
    key: ValueKey(_shift),
    load: _load,
    onUnauthorized: widget.onUnauthorized,
    builder: (context, d, _) => _WeekView(
      onLesson: (l) => openLesson(context, widget.api, l),
      data: d,
      onShift: (k) {
        tick();
        setState(() => _shift += k);
      },
    ),
  );
}

class _WeekView extends StatefulWidget {
  final WeekData data;
  final ValueChanged<int> onShift;
  final ValueChanged<Lesson> onLesson;
  const _WeekView({required this.data, required this.onShift, required this.onLesson});

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<_WeekView> {
  final _keys = List.generate(7, (_) => GlobalKey());
  final _scroll = ScrollController();
  late int _selected;

  @override
  void initState() {
    super.initState();
    final today = now();
    final i = DateTime(today.year, today.month, today.day).difference(widget.data.monday).inDays;
    _selected = i >= 0 && i < 7 ? i : 0;
    if (_selected > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _go(_selected, animate: false));
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
                onPressed: () => widget.onShift(-1),
                icon: Icon(Icons.chevron_left_rounded, color: p.muted),
              ),
              IconButton(
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
          child: SingleChildScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 7; i++)
                  _DayBlock(
                    key: _keys[i],
                    date: d.monday.add(Duration(days: i)),
                    lessons: d.days[iso(d.monday.add(Duration(days: i)))] ?? const [],
                    due: d.due[iso(d.monday.add(Duration(days: i)))] ?? const [],
                    today: iso(d.monday.add(Duration(days: i))) == todayIso,
                    at: t,
                    onLesson: widget.onLesson,
                  ),
              ],
            ),
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
  final List<Deadline> due;
  final bool today;
  final DateTime at;
  final ValueChanged<Lesson>? onLesson;
  const _DayBlock({
    super.key,
    required this.date,
    required this.lessons,
    required this.due,
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
                  Text(due.isEmpty ? 'отдыхай' : 'зато есть что сдать — ниже', style: s.body(13, color: p.muted)),
                ],
              ),
            )
          else
            LessonList(lessons: lessons, at: at, onTap: onLesson),
          for (final x in due)
            Container(
              margin: const EdgeInsets.only(top: Space.s),
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
              decoration: BoxDecoration(
                color: p.danger.withValues(alpha: p.dark ? 0.16 : 0.12),
                borderRadius: BorderRadius.circular(Radii.tile),
              ),
              child: Row(
                children: [
                  Icon(Icons.diamond_rounded, size: 13, color: p.danger),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сдать до ${x.dueTime.isEmpty ? '23:59' : x.dueTime}',
                          style: s.body(12, weight: FontWeight.w600, color: p.danger),
                        ),
                        Text(x.subject, style: s.body(15, weight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
