// «Сдано» (5.79, «Оформление»): отметил срок сданным — тихо (как было),
// капибара радуется или короткое конфетти. Поверх экрана, нажатия не ловит.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/look.dart';
import 'capy.dart';

/// Порадоваться отметке «сдано» так, как выбрано в «Оформлении».
void cheer(BuildContext context) {
  final s = AppStyle.of(context);
  if (s.look.cheer == Cheer.quiet) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: AppStyle(
        p: s.p,
        font: s.font,
        theme: s.theme,
        look: s.look,
        design2: s.design2,
        child: _Cheer(kind: s.look.cheer, onDone: () => entry.remove()),
      ),
    ),
  );
  overlay.insert(entry);
}

class _Cheer extends StatefulWidget {
  final Cheer kind;
  final VoidCallback onDone;
  const _Cheer({required this.kind, required this.onDone});

  @override
  State<_Cheer> createState() => _CheerState();
}

class _CheerState extends State<_Cheer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward().whenComplete(widget.onDone);
  final _seed = math.Random().nextInt(1 << 20);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        if (widget.kind == Cheer.confetti) {
          return CustomPaint(size: Size.infinite, painter: _Confetti(t, _seed, p.accent, p.ok, p.warn));
        }
        // капибара выпрыгивает снизу, радуется и уходит
        final up = Curves.easeOutBack.transform((t / 0.3).clamp(0.0, 1.0));
        final out = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 130),
            child: Opacity(
              opacity: 1 - out,
              child: Transform.translate(
                offset: Offset(0, 80 * (1 - up)),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * up,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: p.cardSolid, shape: BoxShape.circle),
                    child: CapyImage(pose: CapyPose.joy, size: 84, color: p.ok),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Confetti extends CustomPainter {
  final double t;
  final int seed;
  final Color a, b, c;
  const _Confetti(this.t, this.seed, this.a, this.b, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final colors = [a, b, c];
    final fade = t < 0.8 ? 1.0 : (1 - t) / 0.2;
    for (var i = 0; i < 40; i++) {
      final x0 = size.width * r.nextDouble();
      final vx = (r.nextDouble() - 0.5) * 120;
      final vy = -280 - r.nextDouble() * 260;
      final spin = r.nextDouble() * 8;
      final paint = Paint()..color = colors[i % 3].withValues(alpha: fade);
      // вылетают снизу вверх и падают обратно
      final x = x0 + vx * t;
      final y = size.height - 60 + vy * t + 520 * t * t;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(spin * t);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confetti old) => old.t != t;
}
