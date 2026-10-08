// Капибара в углу экрана: по времени суток — утром с кофе, днём за
// компьютером, вечером с лампой, ночью спит. Пока — значок поверх
// картинки и мягкое «дыхание»; кадры анимаций нарисуем отдельно.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common.dart';

enum CapyMood { morning, day, evening, night }

CapyMood moodAt(int hour) {
  if (hour >= 6 && hour < 11) return CapyMood.morning;
  if (hour >= 11 && hour < 18) return CapyMood.day;
  if (hour >= 18 && hour < 23) return CapyMood.evening;
  return CapyMood.night;
}

const _moodIcon = {
  CapyMood.morning: Icons.coffee_rounded,
  CapyMood.day: Icons.laptop_mac_rounded,
  CapyMood.evening: Icons.light_rounded,
  CapyMood.night: Icons.bedtime_rounded,
};

const _moodText = {
  CapyMood.morning: 'Доброе утро. Кофе уже тут',
  CapyMood.day: 'Работаем',
  CapyMood.evening: 'Вечер. Лампа горит, дела тают',
  CapyMood.night: 'Тсс, капибара спит',
};

class CapyBadge extends StatefulWidget {
  final int hour;
  final double size;
  const CapyBadge({super.key, required this.hour, this.size = 52});

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
    final p = AppStyle.of(context).p;
    final mood = moodAt(widget.hour);
    final sleepy = mood == CapyMood.night;
    return Semantics(
      label: _moodText[mood],
      child: GestureDetector(
        onTap: () {
          tick();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(_moodText[mood]!), duration: const Duration(seconds: 2)));
        },
        child: AnimatedBuilder(
          animation: _breath,
          builder: (context, child) {
            final k = math.sin(_breath.value * 2 * math.pi);
            return Transform.scale(scale: 1 + k * (sleepy ? 0.035 : 0.015), child: child);
          },
          child: SizedBox(
            width: widget.size + 8,
            height: widget.size + 8,
            child: Stack(
              children: [
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.dark ? p.cardSolid : p.card,
                    border: Border.all(color: p.line),
                  ),
                  child: ClipOval(
                    child: Opacity(
                      opacity: sleepy ? 0.75 : 1,
                      child: CapyImage(size: widget.size),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.bg, width: 2),
                    ),
                    child: Icon(_moodIcon[mood], size: 13, color: p.onAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Картинка капибары — белый силуэт: в тёмной теме как есть, в светлой
/// «Тетради» — цветом текста, иначе на светлом фоне её не видно.
class CapyImage extends StatelessWidget {
  final double size;
  const CapyImage({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    return Image.asset(
      'assets/capy.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      color: p.dark ? null : p.text,
      colorBlendMode: p.dark ? null : BlendMode.srcIn,
    );
  }
}
