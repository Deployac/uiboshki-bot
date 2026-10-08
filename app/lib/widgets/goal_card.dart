// Экран предмета: цель (sdo_goal.py — без дат и раскладки по времени,
// решение владельца), посещения лекций (attendance.py) и как росли баллы
// (sdo_history.py). Данные — из /api/sdo/grades/<курс>, цель — POST /api/sdo/goal.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'common.dart';

String markWord(String label) => label == 'зачёт' ? 'зачёт' : '«$label»';

String fmtNum(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).replaceAll('.', ',');

class GoalCard extends StatefulWidget {
  final Api api;
  final int courseId;
  final Map<String, dynamic> goal;
  final Color color;
  const GoalCard({super.key, required this.api, required this.courseId, required this.goal, required this.color});

  @override
  State<GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<GoalCard> {
  late Map<String, dynamic> _g = widget.goal;
  String? _error;

  Future<void> _set(String label) async {
    if (label == _g['label']) return;
    tick();
    try {
      final r = await widget.api.post('/sdo/goal/${widget.courseId}', {'label': label});
      HapticFeedback.lightImpact();
      setState(() {
        _g = Map<String, dynamic>.from(r);
        _error = null;
      });
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final g = _g;
    final status = '${g['status'] ?? 'ok'}';
    final (Color tone, String verdict) = switch (status) {
      'done' => (p.ok, '${markWord('${g['label']}')} есть'),
      'tight' => (p.warn, 'впритык'),
      'no' => (p.danger, 'не хватит'),
      _ => (p.ok, 'дойдёшь'),
    };
    final need = (g['need'] as num?) ?? 0;
    final tk = Map<String, dynamic>.from(g['tk'] ?? {});
    final marks = [for (final m in (g['marks'] as List? ?? [])) '$m'];
    final lines = <(IconData, String)>[
      if ((g['open_count'] ?? 0) > 0)
        (Icons.upload_rounded, 'работы: открыто ${g['open_count']} · до +${fmtNum(g['open_points'] ?? 0)}'),
      if ((g['attendance_left'] ?? 0) > 0)
        (Icons.groups_outlined, 'посещения лекций: до +${fmtNum(g['attendance_left'])}'),
      if ((tk['total'] ?? 0) > 0)
        (
          Icons.task_alt_rounded,
          'зачтено ${tk['passed']} из ${tk['total']} · нужно ${tk['need']}'
              '${(tk['left'] ?? 0) > 0 ? ' → из ${tk['open']} открытых зачесть ${tk['left']}' : ''}',
        ),
      if (need > 0 && status != 'done')
        (Icons.auto_awesome_outlined, 'если сдать всё и ходить на лекции — до ${fmtNum(g['best'] ?? 0)}'),
      if ((g['lost_count'] ?? 0) > 0)
        (
          Icons.warning_amber_rounded,
          'ниже порога или срок прошёл: ${g['lost_count']} — не считаю, пригодится, если дадут пересдать',
        ),
      if (g['skip'] is Map) _skipLine(Map<String, dynamic>.from(g['skip']), status),
    ];
    return Tile(
      radius: Radii.card,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          tone.withValues(alpha: p.dark ? 0.28 : 0.16),
          p.cardSolid.withValues(alpha: p.dark ? 0.6 : 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Цель', style: s.title(20)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  verdict,
                  style: s.body(13, weight: FontWeight.w700, color: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.m),
          // Выбор отметки — сегменты, выбранная залита цветом предмета
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(Radii.pill)),
            child: Row(
              children: [
                for (final m in marks)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: m == g['label'],
                      label: 'Цель $m',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _set(m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: m == g['label'] ? widget.color : Colors.transparent,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            m,
                            style: s.body(15, weight: FontWeight.w700, color: m == g['label'] ? Colors.white : p.muted),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          Text(
            need > 0
                ? 'ещё ${fmtNum(need)} ${plural(need.ceil(), 'балл', 'балла', 'баллов')}'
                : 'по баллам уже набрано',
            style: s.title(26, color: need > 0 ? p.text : p.ok),
          ),
          const SizedBox(height: 4),
          Text(
            'до ${markWord('${g['label']}')} — ${fmtNum(g['at'] ?? 0)} из баллов БРС',
            style: s.body(13, color: p.muted),
          ),
          const SizedBox(height: Space.m),
          for (final (ic, text) in lines)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(ic, size: 16, color: p.muted),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(text, style: s.body(14))),
                ],
              ),
            ),
          if (status == 'no') ...[
            const SizedBox(height: Space.m),
            Text(
              tk['reachable'] == false
                  ? 'Открытых работ меньше, чем нужно зачесть: без пересдачи экзамена по БРС не будет.'
                  : 'Даже если сдать всё и ходить на все лекции, будет ${fmtNum(g['best'] ?? 0)} — меньше ${fmtNum(g['at'] ?? 0)}. Можно выбрать цель ниже.',
              style: s.body(13, color: p.danger),
            ),
          ],
          if (_error != null) ...[const SizedBox(height: Space.s), Text(_error!, style: s.body(13, color: p.danger))],
        ],
      ),
    );
  }

  (IconData, String) _skipLine(Map<String, dynamic> skip, String now) {
    final d = DateTime.tryParse('${skip['date']}');
    final day = d == null ? '' : '${d.day} ${monthsGen[d.month - 1]}';
    final after = switch ('${skip['status']}') {
      _ when skip['status'] == now => 'ничего не изменится',
      'done' => 'всё равно есть',
      'tight' => 'станет впритык',
      'no' => 'уже не хватит',
      _ => 'дойдёшь',
    };
    return (Icons.schedule_rounded, 'пропущу лекцию $day: −${fmtNum(skip['value'] ?? 0)} → $after');
  }
}

/// Посещения лекций квадратиками: был, пропуск, ждём балл, впереди.
class AttendanceStrip extends StatelessWidget {
  final Map<String, dynamic> att;
  final Color color;
  const AttendanceStrip({super.key, required this.att, required this.color});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final lectures = [for (final l in (att['lectures'] as List? ?? [])) Map<String, dynamic>.from(l)];
    final total = att['total'] ?? lectures.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final l in lectures)
              Tooltip(
                message: '${l['n']} лекция · ${l['date']}',
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: switch (l['status']) {
                      'ok' => color,
                      'excused' => color.withValues(alpha: 0.5),
                      'miss' => Colors.transparent,
                      _ => p.line,
                    },
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: switch (l['status']) {
                        'miss' => p.danger,
                        'wait' => color,
                        _ => Colors.transparent,
                      },
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.s),
        Text(
          'был на ${att['attended'] ?? 0} из ${att['past'] ?? 0} прошедших · всего $total'
          '${(att['waiting'] ?? 0) > 0 ? ' · ждём балл за ${att['waiting']}' : ''}',
          style: s.body(13, color: p.muted),
        ),
      ],
    );
  }
}

/// Как росли баллы: линия по дням и «+8 за неделю».
class HistoryChart extends StatelessWidget {
  final Map<String, dynamic> history;
  final Color color;
  const HistoryChart({super.key, required this.history, required this.color});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final pts = [
      for (final x in (history['points'] as List? ?? []))
        (DateTime.parse('${x[0]}'), ((x as List)[1] as num).toDouble()),
    ];
    final delta = history['week_delta'] as num?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (delta != null)
          Text(
            '${delta > 0 ? '+' : ''}${fmtNum(delta)} за неделю',
            style: s.body(14, weight: FontWeight.w700, color: delta > 0 ? p.ok : p.muted),
          ),
        const SizedBox(height: Space.s),
        if (pts.length < 2)
          Text(
            'График появится, когда наберётся история: бот запоминает сумму раз в день, когда ты смотришь баллы.',
            style: s.body(13, color: p.muted),
          )
        else
          SizedBox(
            height: 90,
            width: double.infinity,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, k, _) => CustomPaint(painter: _Line(pts, color, p.line, k)),
            ),
          ),
      ],
    );
  }
}

class _Line extends CustomPainter {
  final List<(DateTime, double)> pts;
  final Color c, grid;
  final double k;
  _Line(this.pts, this.c, this.grid, this.k);

  @override
  void paint(Canvas canvas, Size size) {
    final t0 = pts.first.$1.millisecondsSinceEpoch.toDouble();
    final t1 = pts.last.$1.millisecondsSinceEpoch.toDouble();
    final lo = pts.map((e) => e.$2).reduce(math.min), hi = pts.map((e) => e.$2).reduce(math.max);
    final span = hi - lo == 0 ? 1 : hi - lo;
    Offset at((DateTime, double) e) => Offset(
      t1 == t0 ? size.width : (e.$1.millisecondsSinceEpoch - t0) / (t1 - t0) * size.width,
      size.height - 6 - (e.$2 - lo) / span * (size.height - 12),
    );
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), Paint()..color = grid);
    final path = Path()..moveTo(at(pts.first).dx, at(pts.first).dy);
    for (final e in pts.skip(1)) {
      path.lineTo(at(e).dx, at(e).dy);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * k, size.height));
    final fill = Path.from(path)
      ..lineTo(at(pts.last).dx, size.height)
      ..lineTo(at(pts.first).dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withValues(alpha: 0.3), c.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
    if (k >= 1) canvas.drawCircle(at(pts.last), 4.5, Paint()..color = c);
  }

  @override
  bool shouldRepaint(_Line old) => old.k != k || old.c != c;
}
