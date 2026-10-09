// «Сегодня», второй вид (владелец, 09.10, 22А) — как главная в Telegram
// WebApp: эта неделя плитками дней с цветными точками пар, ниже — пары
// выбранного дня теми же карточками, что в главном виде, с номером пары.
// Открывается на сегодня (его пары — сразу из /api/today), остальные дни
// догружаются из запаса телефона и сети; свайп вбок — соседний день.
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/capy.dart';
import '../widgets/common.dart';
import 'lesson.dart';
import 'today.dart';
import 'week.dart' show mondayOf;

class TodayDays extends StatefulWidget {
  final TodayData data;
  final Api api;

  /// Шапка — та же, что в главном виде (группа, погода, переключатель).
  final Widget top;
  const TodayDays({super.key, required this.data, required this.api, required this.top});

  @override
  State<TodayDays> createState() => _TodayDaysState();
}

class _TodayDaysState extends State<TodayDays> {
  late final DateTime _monday = mondayOf(now());
  late final String _today = iso(now());

  /// Пары по датам этой недели; ещё не загруженного дня нет в словаре.
  final Map<String, List<Lesson>> _days = {};
  late int _selected = now().weekday - 1;
  int _dir = 1; // куда уехал день: 1 — вперёд, -1 — назад
  bool _busy = false, _failed = false;

  DateTime _date(int i) => _monday.add(Duration(days: i));

  @override
  void initState() {
    super.initState();
    _days[_today] = widget.data.lessons;
    _fetch(cacheFirst: true);
  }

  @override
  void didUpdateWidget(TodayDays old) {
    super.didUpdateWidget(old);
    // потянул вниз — «Сегодня» обновилось; следом и остальные дни
    if (old.data != widget.data) {
      _days[_today] = widget.data.lessons;
      _fetch();
    }
  }

  Future<Map<String, List<Lesson>>> _load() async {
    final dates = [for (var i = 0; i < 7; i++) _date(i)];
    final res = await Future.wait([for (final d in dates) widget.api.get('/day?date=${iso(d)}')]);
    return {
      for (var i = 0; i < 7; i++)
        iso(dates[i]): [for (final l in (res[i]['lessons'] as List? ?? [])) Lesson.fromJson(l)],
    };
  }

  void _put(Map<String, List<Lesson>> days) => setState(() {
    _days
      ..addAll(days)
      ..[_today] = widget.data.lessons; // сегодня — как в главном виде
    _failed = false;
  });

  Future<void> _fetch({bool cacheFirst = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      if (cacheFirst) {
        final cached = await Api.fromCache(_load);
        if (cached != null && mounted) _put(cached);
      }
      final fresh = await _load();
      if (mounted) _put(fresh);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _busy = false;
    }
  }

  /// Пн–Сб всегда, воскресенье — если в него есть пары или оно сегодня.
  List<int> get _shown => [
    for (var i = 0; i < 7; i++)
      if (i < 6 || (_days[iso(_date(i))]?.isNotEmpty ?? false) || iso(_date(i)) == _today) i,
  ];

  void _go(int i) {
    if (i == _selected) return;
    tick();
    setState(() {
      _dir = i > _selected ? 1 : -1;
      _selected = i;
    });
  }

  void _swipe(int k) {
    final shown = _shown;
    final j = shown.indexOf(_selected) + k;
    if (j >= 0 && j < shown.length) _go(shown[j]);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final t = now();
    final date = _date(_selected);
    final key = iso(date);
    final lessons = _days[key];
    final n = lessons?.length ?? 0;
    final day = key == _today
        ? 'сегодня'
        : '${weekdays[date.weekday - 1].toLowerCase()}, ${date.day} ${monthsGen[date.month - 1]}';
    return GestureDetector(
      // свайп вбок — соседний день; вертикальную прокрутку не трогает
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (e) {
        final v = e.primaryVelocity ?? 0;
        if (v.abs() >= 250) _swipe(v < 0 ? 1 : -1);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          widget.top,
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(child: Text('Эта неделя', style: s.title(28))),
                if (widget.data.week != null) ...[
                  const SizedBox(width: Space.s),
                  Text('${widget.data.week} неделя', style: s.body(13, color: p.muted)),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l - 3),
            child: Row(
              children: [
                for (final i in _shown)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _DayTile(
                        key: ValueKey('day:${iso(_date(i))}'),
                        date: _date(i),
                        lessons: _days[iso(_date(i))],
                        selected: i == _selected,
                        today: iso(_date(i)) == _today,
                        onTap: () => _go(i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Section(n == 0 ? day : '$day · $n ${plural(n, 'пара', 'пары', 'пар')}'),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
            transitionBuilder: (child, anim) {
              final incoming = child.key == ValueKey(key);
              final from = Offset((incoming ? 0.15 : -0.15) * _dir, 0);
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: from, end: Offset.zero).animate(anim),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(key: ValueKey(key), child: _dayBody(context, lessons, t)),
          ),
        ],
      ),
    );
  }

  Widget _dayBody(BuildContext context, List<Lesson>? lessons, DateTime t) {
    if (lessons == null) {
      if (_failed) {
        return Notice(
          title: 'Не загрузилось',
          text: 'Нет связи с сервером — проверь интернет.',
          onRetry: () => _fetch(),
          pose: CapyPose.sad,
        );
      }
      return Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Center(child: CircularProgressIndicator(color: AppStyle.of(context).p.accent, strokeWidth: 2.5)),
      );
    }
    if (lessons.isEmpty) return const Notice(title: 'Пар нет', text: 'Свободный день.', pose: CapyPose.joy);
    return Column(
      children: [
        for (final l in lessons)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: LessonCard(lesson: l, at: t, onTap: () => openLesson(context, widget.api, l)),
          ),
      ],
    );
  }
}

/// Плитка дня: день недели, число и точки пар цветами предметов; выбранный
/// залит акцентом, сегодняшний — в рамке акцента.
class _DayTile extends StatelessWidget {
  final DateTime date;
  final List<Lesson>? lessons;
  final bool selected, today;
  final VoidCallback onTap;
  const _DayTile({
    super.key,
    required this.date,
    required this.lessons,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final n = lessons?.length ?? 0;
    final count = lessons == null ? '' : ', ${n == 0 ? 'пар нет' : '$n ${plural(n, 'пара', 'пары', 'пар')}'}';
    return Semantics(
      button: true,
      selected: selected,
      label: '${dayTitle(date)}$count',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? p.accent : p.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: selected ? p.accent : (today ? p.accent.withValues(alpha: 0.7) : p.line)),
          ),
          child: Column(
            children: [
              Text(weekdaysShort[date.weekday - 1], style: s.body(11, color: selected ? p.onAccent : p.muted)),
              const SizedBox(height: 1),
              Text(
                '${date.day}',
                style: s.body(17, weight: FontWeight.w700, color: selected ? p.onAccent : (today ? p.accent : p.text)),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 5,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final l in (lessons ?? const <Lesson>[]).take(5))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: selected ? p.onAccent : subjectColor(l.title),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
