// Общие кирпичики экранов: фон с подсветкой, карточка, заголовок экрана.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'capy.dart';
import 'capy_refresh.dart';

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

  /// Рамка другого цвета — у идущей пары (по умолчанию линия темы).
  final Color? border;
  const Tile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.l),
    this.color,
    this.gradient,
    this.onTap,
    this.radius = Radii.tile,
    this.border,
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
          border: Border.all(color: border ?? p.line),
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

/// Заголовок экрана: крупное название с короткой прямой чертой под ним (без
/// дуги — решение владельца). Мелких курсивных подписей над ним нет
/// (владелец, 2.4): нужное по смыслу («экзамен», предмет задания) — строкой
/// [sub] под названием обычным шрифтом. Длинное название — мельче, до трёх
/// строк (2.3).
class ScreenTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  /// Строка под названием: «экзамен», «Анализ данных · тест».
  final String? sub;

  /// Строка над заголовком, если в ней не только текст (даты недели со стрелками).
  final Widget? lead;
  const ScreenTitle({super.key, required this.title, this.trailing, this.lead, this.sub});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FitWords(title, style: s.title(titleSize(title, 34)), maxLines: 3),
              if (sub != null && sub!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(sub!, style: s.body(15, color: s.p.muted)),
              ],
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
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, Space.m),
      // строка над заголовком — во всю ширину, кнопки справа её не теснят (Б5)
      child: lead == null
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [lead!, const SizedBox(height: 6), row],
            ),
    );
  }
}

/// Кегль заголовка по длине: длинные названия предметов («Анализ и
/// диагностика финансово-хозяйственной…») — мельче (владелец, 2.3).
double titleSize(String text, double base) {
  final n = text.length;
  if (n > 60) return base * 0.62;
  if (n > 40) return base * 0.72;
  if (n > 26) return base * 0.86;
  return base;
}

/// Крупный заголовок без разрыва слов посередине («Безопасн/ость»,
/// «хозяйственн/ой») и после дефиса («финансово-/хозяйственной»): если самое
/// длинное слово не влезает в строку (узкий экран, крупный системный шрифт),
/// шрифт уменьшается ровно до влезания; с [maxLines] — ещё и пока текст
/// не уляжется в столько строк.
class FitWords extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// Ширина строки, если известна заранее (внутри IntrinsicHeight
  /// LayoutBuilder нельзя); без неё — по месту.
  final double? width;
  final int? maxLines;
  const FitWords(this.text, {super.key, required this.style, this.width, this.maxLines});

  static final _gaps = RegExp(r'[\s/]+');

  /// Слово через дефис не рвётся: после дефиса — «соединитель слов» (U+2060).
  static String glue(String text) => text.replaceAllMapped(RegExp(r'(\S)-(?=\S)'), (m) => '${m[1]}-\u2060');

  Widget _fit(BuildContext context, double max) {
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    final shown = glue(text);
    var size = style.fontSize ?? 14;
    if (max.isFinite) {
      var widest = 0.0;
      for (final w in shown.split(_gaps)) {
        final tp = TextPainter(
          text: TextSpan(text: w, style: style),
          textScaler: scaler,
          textDirection: dir,
        )..layout();
        if (tp.width > widest) widest = tp.width;
        tp.dispose();
      }
      if (widest > max) size = size * max / widest * 0.98;
      // в [maxLines] строк — мельче, но не меньше 60 % от начального
      final floor = (style.fontSize ?? 14) * 0.6;
      while (maxLines != null && size > floor) {
        final tp = TextPainter(
          text: TextSpan(text: shown, style: style.copyWith(fontSize: size)),
          textScaler: scaler,
          textDirection: dir,
          maxLines: maxLines,
        )..layout(maxWidth: max);
        final over = tp.didExceedMaxLines;
        tp.dispose();
        if (!over) break;
        size *= 0.93;
      }
    }
    return Text(
      shown,
      style: size == style.fontSize ? style : style.copyWith(fontSize: size),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) =>
      width != null ? _fit(context, width!) : LayoutBuilder(builder: (context, box) => _fit(context, box.maxWidth));
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

  /// Капибара слева: радостная — «всё хорошо, пусто», грустная — «не вышло».
  final CapyPose? pose;
  const Notice({super.key, required this.title, required this.text, this.onRetry, this.pose});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final words = Column(
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
    );
    // «Пусто, всё хорошо» — капибара выглядывает снизу справа из-за края карточки
    if (pose != null && pose != CapyPose.sad) {
      const size = 84.0;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: Tile(
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: size * CapyPeek.shown + 30),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.l, size + Space.l, Space.l),
                  child: words,
                ),
              ),
              Positioned(
                right: Space.m,
                bottom: 0,
                child: CapyPeek(pose: pose!, size: size),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      child: Tile(
        child: Row(
          children: [
            if (pose != null) ...[CapyImage(pose: pose!, size: 72, color: s.p.muted), const SizedBox(width: Space.l)],
            Expanded(child: words),
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
    _fromCache();
    _reload();
  }

  /// Пока идёт сеть — прошлые данные из запаса телефона, без крутилки.
  Future<void> _fromCache() async {
    final d = await Api.fromCache(widget.load);
    if (d != null && mounted && _data == null) setState(() => _data = d);
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
    if (_data != null) {
      return CapyRefresh(onRefresh: _reload, child: widget.builder(context, _data as T, _reload));
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Notice(title: 'Не загрузилось', text: errorText(_error!), onRetry: _reload, pose: CapyPose.sad),
        ],
      );
    }
    return const CapyLoading();
  }
}
