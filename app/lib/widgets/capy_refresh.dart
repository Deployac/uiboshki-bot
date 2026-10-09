// Капибара, пока грузится (владелец, 09.10, пункт 26 — «все это»): на месте
// крутилки при первой загрузке экрана — сцена с подписью (`CapyLoading`);
// потянул экран вниз — маленькая капибара сверху, без плашки (`CapyRefresh`).
// Сцены идут по кругу: ноутбук, лампа, мяч, мандарин; ночью — спит.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'capy.dart';
import 'common.dart';

enum CapyScene { surf, laptop, lamp, ball, mandarin, sleep }

const sceneText = {
  CapyScene.surf: 'ловлю волну…',
  CapyScene.laptop: 'печатаю…',
  CapyScene.lamp: 'листаю…',
  CapyScene.ball: 'обновляю…',
  CapyScene.mandarin: 'держу мандарин…',
  CapyScene.sleep: 'сплю, но обновляю…',
};

/// Какая сцена следующая: ночью — сон, в остальное время — по кругу.
class CapyScenes {
  // сёрф пока не в круге: владелец (09.10) нарисует капибару на доске в ChatGPT
  static const day = [CapyScene.laptop, CapyScene.lamp, CapyScene.ball, CapyScene.mandarin];
  static int _next = math.Random().nextInt(day.length);

  static CapyScene next(int hour) {
    if (hour >= 23 || hour < 5) return CapyScene.sleep;
    return day[_next++ % day.length];
  }

  /// Для тестов: начать круг с этой сцены.
  static void startAt(CapyScene scene) => _next = math.max(0, day.indexOf(scene));
}

/// «Потяни, чтобы обновить» с капибарой вместо крутилки.
class CapyRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  /// Час для выбора сцены (тесты, стенд); по умолчанию — сейчас.
  final int? hour;
  const CapyRefresh({super.key, required this.onRefresh, required this.child, this.hour});

  /// Высота маленькой сцены сверху.
  static const cardHeight = 56.0;

  @override
  State<CapyRefresh> createState() => _CapyRefreshState();
}

class _CapyRefreshState extends State<CapyRefresh> with TickerProviderStateMixin {
  // 0 — карточка спрятана над экраном, 1 — видна целиком
  late final _pos = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  // пока грузится, экран чуть съезжает вниз — капибара в просвете, а не поверх строк
  late final _gap = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  RefreshIndicatorStatus? _status;
  CapyScene _scene = CapyScene.surf;
  double _drag = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pos.dispose();
    _gap.dispose();
    super.dispose();
  }

  void _onStatus(RefreshIndicatorStatus? s) {
    if (!mounted) return;
    final was = _status;
    _status = s;
    switch (s) {
      case RefreshIndicatorStatus.drag:
        // новый жест — новая сцена (пока капибара на экране, она не меняется)
        if (_pos.value == 0 && !_busy) setState(() => _scene = CapyScenes.next(widget.hour ?? now().hour));
        _drag = 0;
      case RefreshIndicatorStatus.armed:
        if (was == RefreshIndicatorStatus.drag) tick();
      case RefreshIndicatorStatus.snap:
        _pos.animateTo(1, curve: Curves.easeOutBack);
        _gap.animateTo(1, curve: Curves.easeOutCubic);
      case RefreshIndicatorStatus.canceled:
        if (!_busy) _pos.animateTo(0, curve: Curves.easeIn);
      case RefreshIndicatorStatus.done:
      case RefreshIndicatorStatus.refresh:
      case null:
        break;
    }
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        _busy = false;
        _pos.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeInCubic);
        _gap.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeInCubic);
      }
    }
  }

  // Тянет так же, как считает сам RefreshIndicator: карточка выезжает вслед за пальцем.
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || _busy) return false;
    if (_status != RefreshIndicatorStatus.drag && _status != RefreshIndicatorStatus.armed) return false;
    if (n.metrics.axisDirection != AxisDirection.down) return false;
    if (n is ScrollUpdateNotification) {
      _drag -= n.scrollDelta ?? 0;
    } else if (n is OverscrollNotification) {
      _drag -= n.overscroll;
    } else {
      return false;
    }
    // RefreshIndicator взводится на 1/6 высоты экрана — к этому моменту карточка видна вся
    final full = n.metrics.viewportDimension / 6;
    _pos.value = (_drag / full).clamp(0.0, 1.0);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _gap,
            builder: (context, child) =>
                Transform.translate(offset: Offset(0, (CapyRefresh.cardHeight + 8) * _gap.value), child: child),
            child: RefreshIndicator.noSpinner(onRefresh: _run, onStatusChange: _onStatus, child: widget.child),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pos,
                builder: (context, child) {
                  final v = _pos.value;
                  if (v <= 0) return const SizedBox.shrink();
                  return Opacity(
                    opacity: v.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -(CapyRefresh.cardHeight + 8) * (1 - v)),
                      child: child,
                    ),
                  );
                },
                child: _Card(scene: _scene),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Маленькая сцена при «потянуть»: без плашки и подписи (владелец, 09.10).
class _Card extends StatelessWidget {
  final CapyScene scene;
  const _Card({required this.scene});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Обновляю',
    child: Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          key: const Key('capy:refresh'),
          width: 132,
          height: CapyRefresh.cardHeight,
          child: FittedBox(
            child: SizedBox(width: 220, height: 94, child: CapySceneView(scene: scene)),
          ),
        ),
      ),
    ),
  );
}

/// Вместо крутилки, пока экран грузится первый раз: сцена и подпись.
class CapyLoading extends StatefulWidget {
  /// Час для выбора сцены (тесты, стенд); по умолчанию — сейчас.
  final int? hour;
  const CapyLoading({super.key, this.hour});

  @override
  State<CapyLoading> createState() => _CapyLoadingState();
}

class _CapyLoadingState extends State<CapyLoading> {
  late final _scene = CapyScenes.next(widget.hour ?? now().hour);

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Center(
      child: Semantics(
        label: 'Загружаю',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 220, height: 110, child: CapySceneView(scene: _scene)),
            const SizedBox(height: 6),
            Text(sceneText[_scene]!, style: s.body(13, color: s.p.muted)),
          ],
        ),
      ),
    );
  }
}

/// Сама сцена: капибара и то, что вокруг неё движется. Отдельно — для стенда и тестов.
class CapySceneView extends StatefulWidget {
  final CapyScene scene;
  const CapySceneView({super.key, required this.scene});

  static const _period = {
    CapyScene.surf: 2600,
    CapyScene.laptop: 1100,
    CapyScene.lamp: 2400,
    CapyScene.ball: 900,
    CapyScene.mandarin: 1800,
    CapyScene.sleep: 2400,
  };

  @override
  State<CapySceneView> createState() => _CapySceneViewState();
}

class _CapySceneViewState extends State<CapySceneView> with SingleTickerProviderStateMixin {
  late final _t = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: CapySceneView._period[widget.scene]!),
  )..repeat();

  @override
  void didUpdateWidget(CapySceneView old) {
    super.didUpdateWidget(old);
    if (old.scene != widget.scene) {
      _t
        ..duration = Duration(milliseconds: CapySceneView._period[widget.scene]!)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _t,
        builder: (context, _) =>
            Stack(clipBehavior: Clip.hardEdge, children: _scene(p, box.maxWidth, box.maxHeight, _t.value)),
      ),
    );
  }

  List<Widget> _scene(Palette p, double w, double h, double t) {
    final wave = math.sin(t * 2 * math.pi);
    switch (widget.scene) {
      case CapyScene.surf:
        const size = 112.0;
        const sea = Color(0xFF4F8CFF);
        // доска в картинке — на 0,81 высоты: ставим её на гребни волн
        final top = h - 18 - size * 0.81;
        final lift = math.cos(t * 4 * math.pi).abs();
        return [
          Positioned.fill(child: CustomPaint(painter: _Waves(t, sea, front: false))),
          for (var k = 0; k < 3; k++) _spray(w / 2 - 34 - k * 5.0, h - 22 + k * 2.0, (t + k / 3) % 1, sea),
          Positioned(
            left: w / 2 - size / 2 + wave * 8,
            top: top - lift * 5,
            child: Transform.rotate(
              angle: wave * 7 * math.pi / 180,
              alignment: const Alignment(0, 0.62),
              child: const CapyImage(pose: CapyPose.surf, size: size),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _Waves(t, sea, front: true))),
        ];
      case CapyScene.laptop:
        const size = 76.0;
        final left = w / 2 - size / 2;
        final top = h - size - 4;
        return [
          Positioned(
            left: left,
            top: top,
            child: const CapyImage(pose: CapyPose.day, size: size),
          ),
          // три точки над ноутбуком, как «печатает…»
          for (var k = 0; k < 3; k++)
            Positioned(
              left: left + size * 0.66 + k * 8,
              top: top + size * 0.30 - _jump((t - k * 0.14) % 1) * 6,
              child: _dot(6, p.accent.withValues(alpha: 0.5 + 0.5 * _jump((t - k * 0.14) % 1))),
            ),
        ];
      case CapyScene.lamp:
        const size = 76.0;
        final left = w / 2 - size / 2;
        final top = h - size - 4;
        final glow = 0.55 + 0.45 * (0.5 + 0.5 * wave);
        return [
          Positioned(
            left: left + size * 0.76 - 40,
            top: top + size * 0.36 - 40,
            child: Transform.scale(
              scale: 0.92 + 0.14 * (0.5 + 0.5 * wave),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      p.warn.withValues(alpha: 0.45 * glow),
                      p.warn.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.65],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: const CapyImage(pose: CapyPose.evening, size: size),
          ),
        ];
      case CapyScene.ball:
        const size = 74.0;
        // подпрыгивает на мяче, тень внизу сжимается
        final up = math.sin(t * math.pi);
        return [
          Positioned(
            left: w / 2 - 22 + 22 * 0.45 * up,
            bottom: 4,
            child: Container(
              width: 44 * (1 - 0.45 * up),
              height: 6,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4 - 0.25 * up),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            left: w / 2 - size / 2,
            top: h - size - 6 - up * 20,
            child: const CapyImage(pose: CapyPose.joy, size: size),
          ),
        ];
      case CapyScene.mandarin:
        const size = 76.0;
        final left = w / 2 - size / 2;
        final top = h - size - 4;
        return [
          Positioned(
            left: left,
            top: top,
            child: const CapyImage(pose: CapyPose.day, size: size),
          ),
          // мандарин на голове: качается, но не падает
          Positioned(
            left: left + size * 0.50 - 8 + wave * 1.5,
            top: top + size * 0.11 - 15,
            child: Transform.rotate(
              angle: wave * 11 * math.pi / 180,
              alignment: Alignment.bottomCenter,
              child: const _Mandarin(),
            ),
          ),
        ];
      case CapyScene.sleep:
        const size = 74.0;
        final left = w / 2 - size / 2;
        final top = h - size - 2;
        return [
          Positioned(
            left: left,
            top: top,
            child: const CapyImage(pose: CapyPose.night, size: size),
          ),
          for (var k = 0; k < 2; k++)
            Builder(
              builder: (context) {
                final v = (t + k * 0.5) % 1;
                return Positioned(
                  left: left + size * 0.74 + v * 16,
                  top: top + size * 0.10 - v * 20,
                  child: Opacity(
                    opacity: v < 0.3 ? v / 0.3 : 1 - (v - 0.3) / 0.7,
                    child: Text(
                      'z',
                      style: AppStyle.of(context).body(10 + k * 3.0, weight: FontWeight.w800, color: p.accent),
                    ),
                  ),
                );
              },
            ),
        ];
    }
  }

  /// Подскок точки: вверх и вниз за первые 60 % круга.
  static double _jump(double v) => v < 0.6 ? math.sin(v / 0.6 * math.pi) : 0;

  static Widget _dot(double d, Color c) => Container(
    width: d,
    height: d,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  /// Брызги из-под хвоста доски.
  static Widget _spray(double x, double y, double v, Color c) => Positioned(
    left: x - v * 22,
    top: y - v * 16,
    child: Opacity(opacity: v < 0.15 ? v / 0.15 : 1 - v, child: _dot(5 * (1 - 0.5 * v), c.withValues(alpha: 0.9))),
  );
}

/// Две волны бегут влево с разной скоростью: задняя — за капибарой, передняя — поверх доски.
class _Waves extends CustomPainter {
  final double t;
  final Color color;
  final bool front;
  _Waves(this.t, this.color, {required this.front});

  void _wave(Canvas canvas, Size size, double height, double length, double amp, double shift, double alpha) {
    final base = size.height - height + amp;
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width + 1; x += 2) {
      path.lineTo(x, base + amp * math.sin((x + shift) / length * 2 * math.pi));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // за один круг анимации волна сдвигается ровно на длину — без рывка на стыке
    if (front) {
      _wave(canvas, size, 18, 70, 4, t * 2 * 70, 0.5);
    } else {
      _wave(canvas, size, 30, 96, 5, t * 96, 0.3);
    }
  }

  @override
  bool shouldRepaint(_Waves old) => old.t != t || old.color != color || old.front != front;
}

class _Mandarin extends StatelessWidget {
  const _Mandarin();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 19,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          bottom: 0,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-0.3, -0.3),
                colors: [Color(0xFFFFC36B), Color(0xFFF2994A), Color(0xFFD9772A)],
                stops: [0, 0.6, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 7,
          top: 0,
          child: Container(
            width: 7,
            height: 5,
            decoration: const BoxDecoration(
              color: Color(0xFF7BC67E),
              borderRadius: BorderRadius.only(topRight: Radius.circular(6), bottomLeft: Radius.circular(6)),
            ),
          ),
        ),
      ],
    ),
  );
}
