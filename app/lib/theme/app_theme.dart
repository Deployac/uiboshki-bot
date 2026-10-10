// Тема приложения из дизайн-токенов (design/tokens.json → tokens.dart):
// тёмная «Глубина» и светлая «Тетрадь» — как в телефоне или своя (настройка);
// шрифт — настройка («Книжный»: засечки в заголовках и цифрах, «Строгий»: Onest).
import 'package:flutter/material.dart';

import 'tokens.dart';

enum FontChoice { book, strict }

/// Тема: как в телефоне (по умолчанию), всегда светлая или всегда тёмная.
enum ThemeChoice { system, light, dark }

class Palette {
  final bool dark;
  final Color bg, glow1, glow2, card, cardSolid, line, text, muted, accent, onAccent, ok, warn, danger, tabbar;

  const Palette({
    required this.dark,
    required this.bg,
    required this.glow1,
    required this.glow2,
    required this.card,
    required this.cardSolid,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.tabbar,
  });

  static const depth = Palette(
    dark: true,
    bg: ThemeDepth.bg,
    glow1: ThemeDepth.bgGlow1,
    glow2: ThemeDepth.bgGlow2,
    card: ThemeDepth.card,
    cardSolid: ThemeDepth.cardSolid,
    line: ThemeDepth.line,
    text: ThemeDepth.text,
    muted: ThemeDepth.muted,
    accent: ThemeDepth.accent,
    onAccent: ThemeDepth.onAccent,
    ok: ThemeDepth.ok,
    warn: ThemeDepth.warn,
    danger: ThemeDepth.danger,
    tabbar: ThemeDepth.tabbar,
  );

  static const notebook = Palette(
    dark: false,
    bg: ThemeNotebook.bg,
    glow1: ThemeNotebook.bgGlow1,
    glow2: ThemeNotebook.bgGlow2,
    card: ThemeNotebook.card,
    cardSolid: ThemeNotebook.cardSolid,
    line: ThemeNotebook.line,
    text: ThemeNotebook.text,
    muted: ThemeNotebook.muted,
    accent: ThemeNotebook.accent,
    onAccent: ThemeNotebook.onAccent,
    ok: ThemeNotebook.ok,
    warn: ThemeNotebook.warn,
    danger: ThemeNotebook.danger,
    tabbar: ThemeNotebook.tabbar,
  );
}

/// Палитра и шрифт — всем экранам через контекст.
class AppStyle extends InheritedWidget {
  final Palette p;
  final FontChoice font;

  /// Что выбрано в «Тема и шрифт» (палитра [p] — уже по нему).
  final ThemeChoice theme;

  const AppStyle({
    super.key,
    required this.p,
    required this.font,
    this.theme = ThemeChoice.system,
    required super.child,
  });

  static AppStyle of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppStyle>()!;

  String get headFamily => font == FontChoice.book ? 'SourceSerif' : 'Onest';

  TextStyle title(double size, {FontWeight? weight, Color? color}) => TextStyle(
    fontFamily: headFamily,
    fontSize: size,
    fontWeight: weight ?? (font == FontChoice.book ? FontWeight.w500 : FontWeight.w700),
    letterSpacing: -size * 0.03,
    height: 1.1,
    color: color ?? p.text,
  );

  TextStyle number(double size, {Color? color}) => TextStyle(
    fontFamily: headFamily,
    fontSize: size,
    fontWeight: font == FontChoice.book ? FontWeight.w500 : FontWeight.w800,
    letterSpacing: -size * 0.05,
    height: 0.95,
    color: color ?? p.text,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Названия пар, работ и файлов — жирным без засечек при любом шрифте:
  /// длинное «Объектно-ориентированный…» с засечками рвалось и раздувало
  /// карточку (владелец, 09.10, 18Б). Засечки — только у цифр и заголовков.
  TextStyle name(double size, {Color? color}) => TextStyle(
    fontFamily: 'Onest',
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: -size * 0.01,
    height: 1.2,
    color: color ?? p.text,
  );

  TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
      TextStyle(fontFamily: 'Onest', fontSize: size, fontWeight: weight, height: 1.3, color: color ?? p.text);

  TextStyle eyebrow({Color? color}) => font == FontChoice.book
      ? TextStyle(fontFamily: 'SourceSerif', fontStyle: FontStyle.italic, fontSize: 15, color: color ?? p.muted)
      : TextStyle(
          fontFamily: 'Onest',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: color ?? p.muted,
        );

  @override
  bool updateShouldNotify(AppStyle old) => old.p != p || old.font != font || old.theme != theme;
}

/// Цвет предмета: у каждого свой во всём приложении (по названию).
Color subjectColor(String title) {
  var h = 0;
  for (final c in title.toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return subjectColors[h % subjectColors.length];
}

ThemeData materialTheme(Palette p) => ThemeData(
  brightness: p.dark ? Brightness.dark : Brightness.light,
  scaffoldBackgroundColor: p.bg,
  fontFamily: 'Onest',
  colorScheme: ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    surface: p.bg,
  ),
  splashFactory: InkSparkle.splashFactory,
);
