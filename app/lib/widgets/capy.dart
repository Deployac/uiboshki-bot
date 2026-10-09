// Капибара — талисман приложения: 8 поз из ChatGPT (те же, что в WebApp,
// webapp/static/img/capy). В углу «Сегодня» — по времени суток: утро с
// кофе, день за ноутбуком, вечер с книгой и лампой, ночь — спит на мяче;
// радуется, когда сдал или всё хорошо, грустит, когда не загрузилось.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common.dart';

enum CapyPose { morning, day, evening, night, joy, sad, splash }

/// Часы — как в WebApp (core.js: capyForHour).
CapyPose poseAt(int hour) {
  if (hour >= 5 && hour < 12) return CapyPose.morning;
  if (hour >= 12 && hour < 17) return CapyPose.day;
  if (hour >= 17 && hour < 23) return CapyPose.evening;
  return CapyPose.night;
}

const _poseText = {
  CapyPose.morning: 'Доброе утро. Кофе уже тут',
  CapyPose.day: 'Работаем',
  CapyPose.evening: 'Вечер. Лампа горит, дела тают',
  CapyPose.night: 'Тсс, капибара спит',
};

/// Поза — силуэт-маска: цвет даёт тема (как CSS в WebApp), поэтому одна
/// картинка годится и для «Глубины», и для «Тетради».
class CapyImage extends StatelessWidget {
  final CapyPose pose;
  final double size;
  final Color? color;
  const CapyImage({super.key, this.pose = CapyPose.splash, required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    return Image.asset(
      'assets/capy/${pose.name}.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color ?? p.text,
      colorBlendMode: BlendMode.srcIn,
      semanticLabel: null,
      excludeFromSemantics: true,
    );
  }
}

/// Капибара в углу «Сегодня»: поза по времени суток и мягкое «дыхание».
class CapyBadge extends StatefulWidget {
  final int hour;
  final double size;
  const CapyBadge({super.key, required this.hour, this.size = 64});

  @override
  State<CapyBadge> createState() => _CapyBadgeState();
}

class _CapyBadgeState extends State<CapyBadge> with SingleTickerProviderStateMixin {
  late final _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pose = poseAt(widget.hour);
    final sleepy = pose == CapyPose.night;
    return Semantics(
      label: _poseText[pose],
      child: GestureDetector(
        onTap: () {
          tick();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(_poseText[pose]!), duration: const Duration(seconds: 2)));
        },
        child: AnimatedBuilder(
          animation: _breath,
          builder: (context, child) {
            final k = math.sin(_breath.value * 2 * math.pi);
            return Transform.scale(
              scale: 1 + k * (sleepy ? 0.035 : 0.015),
              alignment: Alignment.bottomCenter,
              child: child,
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: CapyImage(key: ValueKey(pose), pose: pose, size: widget.size),
          ),
        ),
      ),
    );
  }
}

/// Радость: капибара подпрыгивает дважды, когда появилась (сдал работу, цель
/// набрана), и ещё раз — если на неё нажать (владелец, 09.10, 17Б).
class CapyHop extends StatefulWidget {
  final CapyPose pose;
  final double size;
  final Color? color;
  const CapyHop({super.key, this.pose = CapyPose.joy, required this.size, this.color});

  @override
  State<CapyHop> createState() => _CapyHopState();
}

class _CapyHopState extends State<CapyHop> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  // высота прыжка в долях роста: большой, приземлился, маленький, приземлился
  static final _jump = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.32).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.32, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 30),
  ]);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      tick();
      _c.forward(from: 0);
    },
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final h = _jump.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -h * widget.size * 0.2),
          child: Transform.rotate(angle: -h * 6 * math.pi / 180, child: child),
        );
      },
      child: CapyImage(pose: widget.pose, size: widget.size, color: widget.color),
    ),
  );
}

/// Грусть («не хватит»): капибара появляется и тихо оседает, один раз.
class CapySigh extends StatelessWidget {
  final double size;
  final Color? color;
  const CapySigh({super.key, required this.size, this.color});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (context, v, child) => Opacity(
      opacity: v,
      child: Transform.translate(
        offset: Offset(0, -size * 0.12 * (1 - v)),
        child: Transform.rotate(angle: v * 4 * math.pi / 180, child: child),
      ),
    ),
    child: CapyImage(pose: CapyPose.sad, size: size, color: color),
  );
}

/// В пустых экранах капибара выглядывает снизу из-за края карточки; ночью
/// спит, над ней плывут «z». Нажал — повернулась (владелец, 09.10, 17Г).
class CapyPeek extends StatefulWidget {
  final CapyPose pose;
  final double size;
  final Color? color;

  /// Час для «ночью спит» (в тестах и на стенде — свой).
  final int? hour;
  const CapyPeek({super.key, this.pose = CapyPose.joy, required this.size, this.color, this.hour});

  /// Сколько капибары видно над краем карточки.
  static const shown = 0.8;

  @override
  State<CapyPeek> createState() => _CapyPeekState();
}

class _CapyPeekState extends State<CapyPeek> with TickerProviderStateMixin {
  late final _rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  AnimationController? _zz;
  bool _turned = false;

  bool get _night {
    final h = widget.hour ?? now().hour;
    return h >= 23 || h < 5;
  }

  @override
  void initState() {
    super.initState();
    _sleep();
  }

  @override
  void didUpdateWidget(CapyPeek old) {
    super.didUpdateWidget(old);
    _sleep();
  }

  /// «z» над спящей — только ночью; наступило утро — перестали.
  void _sleep() {
    if (_night && _zz == null) {
      _zz = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
    } else if (!_night && _zz != null) {
      _zz!.dispose();
      _zz = null;
    }
  }

  @override
  void dispose() {
    _rise.dispose();
    _zz?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    final size = widget.size;
    final color = widget.color ?? p.accent;
    const top = 26.0; // место над головой для «z»
    final visible = size * CapyPeek.shown;
    final rise = CurvedAnimation(parent: _rise, curve: Curves.easeOutBack);
    return GestureDetector(
      onTap: () {
        tick();
        setState(() => _turned = !_turned);
      },
      child: ClipRect(
        child: SizedBox(
          width: size + 18,
          height: visible + top,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedBuilder(
                animation: rise,
                builder: (context, child) =>
                    Positioned(left: 0, top: top + (1 - rise.value) * (visible + 4), child: child!),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _turned ? 1 : 0),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeInOutCubic,
                  builder: (context, v, child) => Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateY(v * math.pi),
                    child: child,
                  ),
                  child: CapyImage(pose: _night ? CapyPose.night : widget.pose, size: size, color: color),
                ),
              ),
              if (_zz != null)
                for (var k = 0; k < 2; k++)
                  AnimatedBuilder(
                    animation: _zz!,
                    builder: (context, _) {
                      final v = (_zz!.value + k * 0.5) % 1;
                      // вылетают из нарисованных «zzz» над головой и тают вверх-вправо
                      return Positioned(
                        left: size * 0.52 + v * 18,
                        top: top + size * 0.02 - v * 26,
                        child: Opacity(
                          opacity: v < 0.3 ? v / 0.3 : 1 - (v - 0.3) / 0.7,
                          child: Text(
                            'z',
                            style: AppStyle.of(context).body(11 + k * 3.0, weight: FontWeight.w800, color: color),
                          ),
                        ),
                      );
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
