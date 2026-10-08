// Нижнее меню «капсула»: выбранная вкладка — пилюля с подписью, остальные —
// только значки. Пилюля плавно перетекает, касание — лёгкий отклик.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'common.dart';

class TabItem {
  final IconData icon;
  final String label;
  const TabItem(this.icon, this.label);
}

class CapsuleTabBar extends StatelessWidget {
  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const CapsuleTabBar({super.key, required this.items, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: Space.m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.tabbar),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 64,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: p.tabbar,
                borderRadius: BorderRadius.circular(Radii.tabbar),
                border: Border.all(color: p.line),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    _Slot(
                      item: items[i],
                      selected: i == index,
                      onTap: () {
                        if (i != index) tick();
                        onTap(i);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final TabItem item;
  final bool selected;
  final VoidCallback onTap;
  const _Slot({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    const dur = Duration(milliseconds: 320);
    const curve = Curves.easeOutCubic;
    return AnimatedFlex(
      flex: selected ? 26 : 10,
      duration: dur,
      curve: curve,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: dur,
            curve: curve,
            decoration: BoxDecoration(
              color: selected ? p.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            alignment: Alignment.center,
            child: ClipRect(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 22, color: selected ? p.onAccent : p.muted),
                  AnimatedSize(
                    duration: dur,
                    curve: curve,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 7),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: s.body(14, weight: FontWeight.w600, color: p.onAccent),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Expanded с анимацией доли: пилюля плавно растёт, соседи сжимаются.
class AnimatedFlex extends ImplicitlyAnimatedWidget {
  final int flex;
  final Widget child;
  const AnimatedFlex({super.key, required this.flex, required this.child, required super.duration, super.curve});

  @override
  AnimatedWidgetBaseState<AnimatedFlex> createState() => _AnimatedFlexState();
}

class _AnimatedFlexState extends AnimatedWidgetBaseState<AnimatedFlex> {
  Tween<double>? _flex;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _flex = visitor(_flex, widget.flex.toDouble(), (v) => Tween<double>(begin: v as double)) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) => Expanded(flex: (_flex!.evaluate(animation) * 10).round(), child: widget.child);
}
