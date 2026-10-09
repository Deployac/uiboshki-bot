// «Неделя», второй вид (владелец, 09.10, 22А; переехал сюда с «Сегодня»):
// дни недели плитками с цветными точками пар, ниже — пары выбранного дня
// карточками с номером пары. Открывается на сегодня (в другой неделе — на
// первом дне с парами); свайп вбок листает недели, как и в ленте.
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/capy.dart';
import '../widgets/common.dart';
import 'today.dart' show LessonCard;
import 'week.dart' show WeekData;

class WeekDays extends StatefulWidget {
  final WeekData data;
  final ValueChanged<Lesson> onLesson;
  const WeekDays({super.key, required this.data, required this.onLesson});

  @override
  State<WeekDays> createState() => _WeekDaysState();
}

class _WeekDaysState extends State<WeekDays> {
  late final String _today = iso(now());
  late int _selected = _start();
  int _dir = 1; // куда уехал день: 1 — вперёд, -1 — назад

  DateTime _date(int i) => widget.data.monday.add(Duration(days: i));
  List<Lesson> _lessons(int i) => widget.data.days[iso(_date(i))] ?? const [];

  int _start() {
    for (var i = 0; i < 7; i++) {
      if (iso(_date(i)) == _today) return i;
    }
    for (var i = 0; i < 7; i++) {
      if (_lessons(i).isNotEmpty) return i;
    }
    return 0;
  }

  /// Пн–Сб всегда, воскресенье — если в него есть пары или оно сегодня.
  List<int> get _shown => [
    for (var i = 0; i < 7; i++)
      if (i < 6 || _lessons(i).isNotEmpty || iso(_date(i)) == _today) i,
  ];

  void _go(int i) {
    if (i == _selected) return;
    tick();
    setState(() {
      _dir = i > _selected ? 1 : -1;
      _selected = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = now();
    final date = _date(_selected);
    final key = iso(date);
    final lessons = _lessons(_selected);
    final n = lessons.length;
    final day = key == _today
        ? 'сегодня'
        : '${weekdays[date.weekday - 1].toLowerCase()}, ${date.day} ${monthsGen[date.month - 1]}';
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
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
                      lessons: _lessons(i),
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
          child: KeyedSubtree(
            key: ValueKey(key),
            child: lessons.isEmpty
                ? const Notice(title: 'Пар нет', text: 'Свободный день.', pose: CapyPose.joy)
                : Column(
                    children: [
                      for (final l in lessons)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                          child: LessonCard(lesson: l, at: t, onTap: () => widget.onLesson(l)),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Плитка дня: день недели, число и точки пар цветами предметов; выбранный
/// залит акцентом, сегодняшний — в рамке акцента.
class _DayTile extends StatelessWidget {
  final DateTime date;
  final List<Lesson> lessons;
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
    final n = lessons.length;
    final count = ', ${n == 0 ? 'пар нет' : '$n ${plural(n, 'пара', 'пары', 'пар')}'}';
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
                      for (final l in lessons.take(5))
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
