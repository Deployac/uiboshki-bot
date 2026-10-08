// Общие кирпичики экранов: фон с подсветкой, карточка, заголовок экрана.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// «Сейчас». Для стенда и скриншотов время можно сдвинуть: --dart-define=NOW=2026-10-08T10:07:00+03:00
DateTime now() {
  final shift = _shift;
  return shift == null ? DateTime.now() : DateTime.now().add(shift);
}

const _fakeNow = String.fromEnvironment('NOW');
final Duration? _shift = _fakeNow.isEmpty ? null : DateTime.parse(_fakeNow).difference(_started);
final _started = DateTime.now();

/// Лёгкий отклик на касание — как в системе, без «дребезга».
void tick() => HapticFeedback.selectionClick();

/// Фон экрана: цвет темы и две мягкие подсветки сверху и снизу.
class Backdrop extends StatelessWidget {
  final Widget child;
  final Color? tint;
  const Backdrop({super.key, required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    return DecoratedBox(
      decoration: BoxDecoration(color: p.bg),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -1.1),
                  radius: 1.2,
                  colors: [
                    (tint ?? p.glow1).withValues(alpha: p.dark ? 0.85 : 0.6),
                    p.bg.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-1, 1.2),
                  radius: 1.1,
                  colors: [
                    p.glow2.withValues(alpha: p.dark ? 0.8 : 0.5),
                    p.bg.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class Tile extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;
  const Tile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.l),
    this.color,
    this.gradient,
    this.onTap,
    this.radius = Radii.tile,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    final r = BorderRadius.circular(radius);
    return Material(
      color: Colors.transparent,
      // подсветка нажатия у строк внутри карточки — по её скруглённым углам
      shape: RoundedRectangleBorder(borderRadius: r),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? p.card) : null,
          gradient: gradient,
          borderRadius: r,
          border: Border.all(color: p.line),
        ),
        child: InkWell(
          borderRadius: r,
          onTap: onTap == null
              ? null
              : () {
                  tick();
                  onTap!();
                },
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Заголовок экрана: строка-подпись курсивом и крупное название с короткой
/// прямой чертой под ним (без дуги — решение владельца).
class ScreenTitle extends StatelessWidget {
  final String eyebrow, title;
  final Widget? trailing;
  const ScreenTitle({super.key, required this.eyebrow, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow, style: s.eyebrow()),
                const SizedBox(height: 6),
                Text(title, style: s.title(34)),
                const SizedBox(height: 10),
                Container(
                  width: 34,
                  height: 3,
                  decoration: BoxDecoration(color: s.p.accent, borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Подпись раздела внутри экрана: «Весь день», «На неделе».
class Section extends StatelessWidget {
  final String text;
  const Section(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.s),
    child: Text(text, style: AppStyle.of(context).eyebrow()),
  );
}

/// Пусто или ошибка — спокойная карточка с подсказкой и кнопкой «Ещё раз».
class Notice extends StatelessWidget {
  final String title, text;
  final VoidCallback? onRetry;
  const Notice({super.key, required this.title, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: s.body(17, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(text, style: s.body(14, color: s.p.muted)),
            if (onRetry != null) ...[
              const SizedBox(height: Space.m),
              TextButton(
                onPressed: onRetry,
                child: Text('Ещё раз', style: s.body(15, color: s.p.accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Загрузка экрана: Future → данные, ошибка или «потяни, чтобы обновить».
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  final VoidCallback? onUnauthorized;
  const Loader({super.key, required this.load, required this.builder, this.onUnauthorized});

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (e is Unauthorized) {
        widget.onUnauthorized?.call();
        return;
      }
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    if (_data != null) {
      return RefreshIndicator(color: p.accent, onRefresh: _reload, child: widget.builder(context, _data as T, _reload));
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Notice(title: 'Не загрузилось', text: 'Нет связи с сервером — проверь интернет.', onRetry: _reload),
        ],
      );
    }
    return Center(child: CircularProgressIndicator(color: p.accent, strokeWidth: 2.5));
  }
}
