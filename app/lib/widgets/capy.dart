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
