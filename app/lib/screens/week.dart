// «Неделя» — два вида пар, переключатель значками справа сверху, выбор
// запоминается (владелец, 09.10: переехал сюда с «Сегодня»).
// Лента: вся неделя одной лентой, сверху полоса дней с точками пар. Нажал
// день — лента плавно едет к нему; открывается сразу на сегодняшнем дне,
// прошедшие — выше, до них можно долистать (19Б). По дням — плитки дней и
// пары выбранного (week_days.dart). В обоих видах соседняя неделя — свайпом
// вбок или стрелками у дат недели.
// Сроки сдачи тут не показываем — для них вкладка «Сдать» (владелец, 09.10).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'lesson.dart';
import 'search.dart';
import 'today.dart' show LessonList;
import 'week_days.dart';

class WeekData {
  final int? number;
  final DateTime monday;
  final Map<String, List<Lesson>> days;
  WeekData(this.number, this.monday, this.days);
}

/// Пустой день — одинаково в обоих видах недели (владелец, 2.13).
const noLessonsTitle = 'Пар нет', noLessonsText = 'Свободный день';

/// Подпись дня в обоих видах: «Вторник, 6 октября · сегодня».
String dayHead(DateTime date, {bool today = false}) => today ? '${dayTitle(date)} · сегодня' : dayTitle(date);

DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

class WeekScreen extends StatefulWidget {
  final Api api;
  final VoidCallback? onUnauthorized;
  const WeekScreen({super.key, required this.api, this.onUnauthorized});

  /// Какой вид открыт: 'list' — лента, 'days' — по дням.
  static const viewKey = 'uib_week_view';

  /// Где выбор лежал, пока переключатель был на «Сегодня»: 'days' — по дням.
  static const oldViewKey = 'uib_today_view';

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  int _shift = 0;
  int _dir = 1; // куда уехала неделя: 1 — вперёд, -1 — назад

  /// Вид по дням; null — выбор ещё читается из памяти телефона.
  bool? _days;

  @override
  void initState() {
    super.initState();
    _readView();
  }

  Future<void> _readView() async {
    var days = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(WeekScreen.viewKey) ?? prefs.getString(WeekScreen.oldViewKey);
      days = v == 'days';
    } catch (_) {}
    if (mounted) setState(() => _days = days);
  }

  Future<void> _setView(bool days) async {
    if (days == _days) return;
    tick();
    setState(() => _days = days);
    try {
      await (await SharedPreferences.getInstance()).setString(WeekScreen.viewKey, days ? 'days' : 'list');
    } catch (_) {}
  }

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
  Widget build(BuildContext context) {
    final days = _days;
    if (days == null) return const SizedBox.shrink();
    return GestureDetector(
      // свайп вбок — соседняя неделя в обоих видах; вертикальную прокрутку не трогает
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
            days: days,
            onView: _setView,
          ),
        ),
      ),
    );
  }
}

class _WeekView extends StatefulWidget {
  final WeekData data;
  final ValueChanged<int> onShift;
  final ValueChanged<Lesson> onLesson;

  /// Поиск расписания любой группы, преподавателя, аудитории.
  final VoidCallback onSearch;

  /// Вид по дням вместо ленты и его переключатель.
  final bool days;
  final ValueChanged<bool> onView;
  const _WeekView({
    required this.data,
    required this.onShift,
    required this.onLesson,
    required this.onSearch,
    required this.days,
    required this.onView,
  });

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
          title: 'Неделя',
          lead: _WeekLabel(text: d.number != null ? '${d.number} неделя · $range' : range, onShift: widget.onShift),
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
              const SizedBox(width: 2),
              ViewToggle(days: widget.days, onChanged: widget.onView),
            ],
          ),
        ),
        if (widget.days)
          Expanded(
            child: WeekDays(data: d, onLesson: widget.onLesson),
          )
        else ...[
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
      ],
    );
  }
}

/// Номер и даты недели, по бокам стрелки на соседние недели.
class _WeekLabel extends StatelessWidget {
  final String text;
  final ValueChanged<int> onShift;
  const _WeekLabel({required this.text, required this.onShift});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    Widget arrow(IconData icon, String tip, int k) => Tooltip(
      message: tip,
      child: Semantics(
        button: true,
        label: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onShift(k),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Icon(icon, size: 20, color: s.p.muted),
          ),
        ),
      ),
    );
    return Transform.translate(
      offset: const Offset(-4, 0), // стрелка — по краю заголовка
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow(Icons.chevron_left_rounded, 'Прошлая неделя', -1),
          Flexible(
            child: Text(text, style: s.eyebrow(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          arrow(Icons.chevron_right_rounded, 'Следующая неделя', 1),
        ],
      ),
    );
  }
}

/// Переключатель двух видов недели — значками, без подписей (владелец, 09.10):
/// лента и по дням.
class ViewToggle extends StatelessWidget {
  final bool days;
  final ValueChanged<bool> onChanged;
  const ViewToggle({super.key, required this.days, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    Widget seg(IconData icon, String tip, bool on, bool value) => Tooltip(
      message: tip,
      child: Semantics(
        button: true,
        selected: on,
        label: tip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: 36,
            height: 30,
            decoration: BoxDecoration(
              color: on ? p.accent : p.accent.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: on ? p.onAccent : p.muted),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(13)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(Icons.view_agenda_outlined, 'Лентой', !days, false),
          const SizedBox(width: 2),
          seg(Icons.calendar_view_week_rounded, 'По дням', days, true),
        ],
      ),
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
            child: Text(dayHead(date, today: today), style: s.eyebrow(color: today ? p.text : p.muted)),
          ),
          if (lessons.isEmpty)
            Tile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(noLessonsTitle, style: s.body(17, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(noLessonsText, style: s.body(13, color: p.muted)),
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
