// «Оформление» (5.79, второй круг дизайна, Никита 12.10): все настройки вида
// в одном экране — сверху живой пример, ниже выборы группами. По умолчанию
// всё как было; «Вернуть как было» убирает новое разом. Сервер может
// выключить экран целиком (features.design2) — тогда в «Ещё» старый лист
// «Тема и шрифт».
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/look.dart';
import '../theme/tokens.dart';
import '../widgets/cheer.dart';
import '../widgets/common.dart';
import 'files.dart' show BackRow;
import 'today.dart' show LessonCard, LessonList;

class LookScreen extends StatelessWidget {
  final ValueChanged<FontChoice> onFont;
  final ValueChanged<ThemeChoice>? onTheme;
  final ValueChanged<Look>? onLook;
  const LookScreen({super.key, required this.onFont, this.onTheme, this.onLook});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final look = s.look;
    void set(Look l) {
      tick();
      onLook?.call(l);
    }

    final sun = moscowSun(now());
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final changed = look != Look.classic || s.font.index > 1 || s.theme == ThemeChoice.sunset;

    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.xxl),
            children: [
              const BackRow(),
              const ScreenTitle(title: 'Оформление'),
              const Padding(padding: EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0), child: _Preview()),

              const Section('когда тёмная'),
              _Pad(
                _Seg<ThemeChoice>(
                  id: 'theme',
                  value: s.theme,
                  items: const [
                    (ThemeChoice.system, 'Как в телефоне'),
                    (ThemeChoice.sunset, 'По закату'),
                    (ThemeChoice.light, 'Светлая'),
                    (ThemeChoice.dark, 'Тёмная'),
                  ],
                  onPick: onTheme == null ? null : (t) => onTheme!(t),
                ),
              ),
              if (s.theme == ThemeChoice.sunset)
                _Hint('Сегодня тёмная с ${hm(sun.set)} до ${hm(sun.rise)} завтра, за час до заката фон мягко темнеет.'),

              const Section('светлая тема'),
              _Pad(
                Row(
                  children: [
                    for (final t in LightTheme.values) ...[
                      if (t != LightTheme.values.first) const SizedBox(width: Space.s),
                      Expanded(
                        child: _Swatch(
                          key: Key('look:light:${t.name}'),
                          palette: Palette.ofLight(t),
                          paper: t == LightTheme.notebook ? look.paper : Paper.smooth,
                          title: t == LightTheme.notebook ? 'Тетрадь' : 'Кампус',
                          sub: t == LightTheme.notebook ? 'тёплая бумага' : 'белая, синий акцент',
                          selected: look.light == t,
                          onTap: () => set(look.copyWith(light: t)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (look.light == LightTheme.notebook) ...[
                const SizedBox(height: Space.s),
                _Pad(
                  _Seg<Paper>(
                    id: 'paper',
                    value: look.paper,
                    items: const [
                      (Paper.smooth, 'Гладкая'),
                      (Paper.cell, 'Клетка'),
                      (Paper.line, 'Линейка'),
                      (Paper.dots, 'Точки'),
                      (Paper.grid, 'Милли­метровка'),
                    ],
                    onPick: (v) => onLook?.call(look.copyWith(paper: v)),
                    small: true,
                  ),
                ),
              ],

              const Section('тёмная тема'),
              _Pad(
                Row(
                  children: [
                    for (final t in DarkTheme.values) ...[
                      if (t != DarkTheme.values.first) const SizedBox(width: Space.s),
                      Expanded(
                        child: _Swatch(
                          key: Key('look:dark:${t.name}'),
                          palette: Palette.ofDark(t),
                          paper: Paper.smooth,
                          title: t == DarkTheme.depth ? 'Глубина' : 'Библиотека',
                          sub: t == DarkTheme.depth ? 'синее свечение' : 'тёмно-зелёная',
                          selected: look.dark == t,
                          onTap: () => set(look.copyWith(dark: t)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Section('шрифт заголовков'),
              _Pad(
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: Space.s,
                  crossAxisSpacing: Space.s,
                  childAspectRatio: 1.9,
                  children: [
                    for (final f in FontChoice.values)
                      _FontCard(
                        choice: f,
                        selected: s.font == f,
                        onTap: () {
                          tick();
                          onFont(f);
                        },
                      ),
                  ],
                ),
              ),

              const Section('пары на «сегодня»'),
              _Pad(
                _Seg<DayView>(
                  id: 'day',
                  value: look.day,
                  items: const [(DayView.cards, 'Карточками'), (DayView.rows, 'Строками')],
                  onPick: (v) => onLook?.call(look.copyWith(day: v)),
                ),
              ),
              if (look.day == DayView.cards) ...[
                const SizedBox(height: Space.s),
                _Pad(
                  _Seg<CardStyle>(
                    id: 'card',
                    value: look.card,
                    items: const [(CardStyle.tint, 'С цветом'), (CardStyle.stripe, 'С полоской')],
                    onPick: (v) => onLook?.call(look.copyWith(card: v)),
                  ),
                ),
              ],

              const Section('когда отметил «сдано»'),
              _Pad(
                _Seg<Cheer>(
                  id: 'cheer',
                  value: look.cheer,
                  items: const [(Cheer.quiet, 'Тихо'), (Cheer.capy, 'Капибара'), (Cheer.confetti, 'Конфетти')],
                  onPick: (v) {
                    onLook?.call(look.copyWith(cheer: v));
                    // сразу показать, как это будет (после перестройки темы)
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) cheer(context);
                    });
                  },
                ),
              ),

              if (changed) ...[
                const SizedBox(height: Space.xl),
                Center(
                  child: TextButton.icon(
                    key: const Key('look:reset'),
                    onPressed: () {
                      tick();
                      onLook?.call(Look.classic);
                      if (s.font.index > 1) onFont(FontChoice.book);
                      if (s.theme == ThemeChoice.sunset) onTheme?.call(ThemeChoice.system);
                    },
                    icon: Icon(Icons.undo_rounded, color: p.muted),
                    label: Text('Вернуть как было', style: s.body(15, color: p.muted)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  final Widget child;
  const _Pad(this.child);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.l),
    child: child,
  );
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, 0),
      child: Text(text, style: s.body(13, color: s.p.muted)),
    );
  }
}

/// Живой пример: фон темы (с бумагой), заголовок выбранным шрифтом и пары
/// так, как они будут на «Сегодня».
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final t = now();
    final day = DateTime(t.year, t.month, t.day);
    String hm(DateTime x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
    Lesson at(int h, int m, String title, String kind, String room, String teacher, String n) {
      final a = day.add(Duration(hours: h, minutes: m));
      final b = a.add(const Duration(minutes: 90));
      return Lesson(
        start: hm(a),
        end: hm(b),
        title: title,
        kind: kind,
        room: room,
        teacher: teacher,
        status: '',
        number: n,
        startAt: a,
        endAt: b,
      );
    }

    final lessons = [
      at(9, 0, 'Анализ данных', 'лекция', 'А-332 (МП-1)', 'Иванова А. С.', '1'),
      at(10, 40, 'Основы предпринимательства', 'практика', 'Г-412 (МП-1)', '', '2'),
    ];
    // «сейчас» — середина первой пары, чтобы было видно, как выглядит идущая
    final now0 = day.add(const Duration(hours: 9, minutes: 40));
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.tile),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.tile),
          border: Border.all(color: p.line),
        ),
        child: Backdrop(
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Идёт первая пара', style: s.title(26)),
                const SizedBox(height: Space.m),
                if (s.look.day == DayView.rows)
                  LessonList(lessons: lessons, at: now0)
                else
                  for (final l in lessons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s),
                      child: LessonCard(lesson: l, at: now0),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Выбор из нескольких — капсулами в ряд, выбранная залита акцентом.
class _Seg<T extends Enum> extends StatelessWidget {
  final String id;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T>? onPick;
  final bool small;
  const _Seg({required this.id, required this.value, required this.items, required this.onPick, this.small = false});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final r = BorderRadius.circular(Radii.chip);
    return Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (final (v, label) in items)
          Semantics(
            selected: v == value,
            button: true,
            child: Material(
              color: v == value ? p.accent : p.card,
              shape: RoundedRectangleBorder(
                borderRadius: r,
                side: BorderSide(color: v == value ? p.accent : p.line),
              ),
              child: InkWell(
                key: Key('look:$id:${v.name}'),
                borderRadius: r,
                onTap: onPick == null || v == value
                    ? null
                    : () {
                        tick();
                        onPick!(v);
                      },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14, vertical: small ? 8 : 10),
                  child: Text(
                    label,
                    style: s.body(
                      small ? 13.5 : 14.5,
                      weight: FontWeight.w600,
                      color: v == value ? p.onAccent : p.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Тема образцом: её фон, карточка, акцент и строки текста.
class _Swatch extends StatelessWidget {
  final Palette palette;
  final Paper paper;
  final String title, sub;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({
    super.key,
    required this.palette,
    required this.paper,
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final q = palette;
    final r = BorderRadius.circular(Radii.tile);
    Widget bar(double w, Color c) => Container(
      width: w,
      height: 6,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: r,
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: selected ? p.accent : p.line, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.tile - 4),
                child: Container(
                  height: 78,
                  color: q.bg,
                  child: Stack(
                    children: [
                      if (paper != Paper.smooth)
                        Positioned.fill(child: CustomPaint(painter: PaperPainter(paper, q.text))),
                      Positioned(
                        left: 10,
                        right: 10,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: q.dark ? q.cardSolid : q.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: q.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(54, q.text),
                              const SizedBox(height: 5),
                              bar(34, q.muted),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 8,
                                    decoration: BoxDecoration(color: q.accent, borderRadius: BorderRadius.circular(4)),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(color: q.ok, shape: BoxShape.circle),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: s.body(14.5, weight: FontWeight.w600)),
                    Text(sub, style: s.body(12, color: p.muted)),
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

/// Шрифт заголовков образцом «Аа 73» — самим шрифтом.
class _FontCard extends StatelessWidget {
  final FontChoice choice;
  final bool selected;
  final VoidCallback onTap;
  const _FontCard({required this.choice, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final (family, weight, size, title, sub) = switch (choice) {
      FontChoice.book => ('SourceSerif', FontWeight.w500, 26.0, 'Книжный', 'с засечками'),
      FontChoice.strict => ('Onest', FontWeight.w800, 26.0, 'Строгий', 'ровный'),
      FontChoice.hand => ('Neucha', FontWeight.w400, 28.0, 'Рукописный', 'как от руки'),
      FontChoice.wide => ('Unbounded', FontWeight.w500, 21.0, 'Широкий', 'плакатный'),
    };
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.tile),
          border: Border.all(color: selected ? p.accent : Colors.transparent, width: 2),
        ),
        child: Tile(
          key: Key('look:font:${choice.name}'),
          onTap: selected ? null : onTap,
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 10),
          child: Row(
            children: [
              Text(
                'Аа',
                style: TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, color: p.text, height: 1),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: s.body(14, weight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sub,
                      style: s.body(12, color: p.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
