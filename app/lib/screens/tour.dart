// Знакомство при первом запуске (владелец, 09.10, 2.8): пять коротких шагов
// поверх самих экранов — вкладка под шагом открывается, меню-капсула
// подсвечена, остальное притушено. «Дальше» / «Пропустить»; повторить —
// «Ещё → Как пользоваться».
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class TourStep {
  final IconData icon;
  final String title, text;

  /// Какая вкладка открыта под шагом (shell.dart, tabs).
  final int tab;
  const TourStep(this.icon, this.title, this.text, this.tab);
}

const tourSteps = [
  TourStep(
    Icons.space_dashboard_outlined,
    'Что где',
    'Сегодня — пары и что дальше. Неделя — всё расписание. Сдать — сроки и заметки. '
        'Учёба — баллы и цели. Ещё — настройки.',
    0,
  ),
  TourStep(
    Icons.swipe_rounded,
    'Листай недели',
    'Проведи по неделе влево или вправо — откроется соседняя. Нажми на день сверху — лента приедет к нему.',
    1,
  ),
  TourStep(
    Icons.task_alt_rounded,
    'Сдал — смахни вправо',
    'Смахни срок вправо — он отметится «Сдано». Нажми на срок — сдать файлом, напомнить или изменить.',
    2,
  ),
  TourStep(
    Icons.touch_app_outlined,
    'Нажми на пару',
    'Откроется карточка пары: кабинет и корпус, преподаватель, файлы и баллы по предмету.',
    0,
  ),
  TourStep(
    Icons.flag_outlined,
    'Цель по предмету',
    'Открой предмет и выбери оценку — капибара посчитает, сколько баллов и работ не хватает.',
    3,
  ),
];

/// Показать тур. onStep — открыть вкладку шага; barRect — где меню-капсула
/// (подсветить), null — без подсветки.
Future<void> showTour(BuildContext context, {required ValueChanged<int> onStep, Rect? Function()? barRect}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, appear, _) => FadeTransition(
        opacity: appear,
        child: TourOverlay(onStep: onStep, barRect: barRect),
      ),
    );

class TourOverlay extends StatefulWidget {
  final ValueChanged<int> onStep;
  final Rect? Function()? barRect;
  const TourOverlay({super.key, required this.onStep, this.barRect});

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  int _i = 0;

  void _next() {
    tick();
    if (_i + 1 >= tourSteps.length) return _close();
    setState(() => _i++);
    widget.onStep(tourSteps[_i].tab);
  }

  void _close() {
    widget.onStep(0);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final step = tourSteps[_i];
    final last = _i == tourSteps.length - 1;
    final mq = MediaQuery.of(context);
    final hole = widget.barRect?.call();
    // карточка — над капсулой (её и подсвечиваем), а без неё — у нижнего края
    final bottom = hole != null ? mq.size.height - hole.top + Space.l : mq.viewPadding.bottom + Space.l;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _Dim(color: Colors.black.withValues(alpha: 0.55), hole: hole),
            ),
          ),
          Positioned(
            left: Space.l,
            right: Space.l,
            bottom: bottom,
            top: mq.viewPadding.top + Space.l,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                reverse: true,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: Container(
                    key: ValueKey('tour:$_i'),
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
                    decoration: BoxDecoration(
                      color: p.cardSolid,
                      borderRadius: BorderRadius.circular(Radii.card),
                      border: Border.all(color: p.line),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: p.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(step.icon, color: p.accent),
                            ),
                            const Spacer(),
                            // шаги точками: где ты сейчас
                            for (var k = 0; k < tourSteps.length; k++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                margin: const EdgeInsets.only(left: 5),
                                width: k == _i ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: k == _i ? p.accent : p.line,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.m),
                        Text(step.title, style: s.title(26)),
                        const SizedBox(height: Space.s),
                        Text(step.text, style: s.body(15, color: p.muted)),
                        const SizedBox(height: Space.m),
                        // узкий экран и крупный шрифт — надписи чуть мельче, а не за край
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (!last)
                              Flexible(
                                child: TextButton(
                                  onPressed: _close,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Пропустить',
                                      style: s.body(15, weight: FontWeight.w600, color: p.muted),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: Space.s),
                            Flexible(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: p.accent,
                                  foregroundColor: p.onAccent,
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                                ),
                                onPressed: _next,
                                child: FittedBox(fit: BoxFit.scaleDown, child: Text(last ? 'Понятно' : 'Дальше')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Притушенный экран с окном-подсветкой (скруглённым, как капсула).
class _Dim extends CustomPainter {
  final Color color;
  final Rect? hole;
  const _Dim({required this.color, this.hole});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      path
        ..addRRect(RRect.fromRectAndRadius(hole!.inflate(4), const Radius.circular(Radii.tabbar + 4)))
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Dim old) => old.color != color || old.hole != hole;
}
