// Тёмные оттенки предметов в светлых темах нового дизайна (5.79.6, Никита
// 12.10): яркие цвета на бумаге «Тетради» читались плохо (контраст 1,6–2,6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiboshki/theme/app_theme.dart';
import 'package:uiboshki/theme/tokens.dart';

AppStyle style(Palette p, {bool design2 = true}) =>
    AppStyle(p: p, font: FontChoice.book, design2: design2, child: const SizedBox());

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  const titles = ['Анализ данных', 'Моделирование бизнес-процессов', 'Основы бизнес-анализа в ИТ-сфере', 'Физкультура'];

  test('светлые темы нового дизайна — тёмный оттенок, читается на фоне и под белым текстом', () {
    expect(subjectInkColors.length, subjectColors.length);
    for (final p in [Palette.notebook, Palette.campus]) {
      final s = style(p);
      expect(s.darkInk, isTrue);
      for (final t in titles) {
        expect(s.ink(t), isNot(subjectColor(t)));
      }
      for (final c in subjectInkColors) {
        expect(contrast(c, p.bg), greaterThanOrEqualTo(4.4));
        expect(contrast(c, Colors.white), greaterThanOrEqualTo(4.5));
      }
    }
    // тот же предмет — тот же оттенок, только темнее
    expect(
      style(Palette.notebook).ink(titles.first),
      subjectInkColors[subjectColors.indexOf(subjectColor(titles.first))],
    );
  });

  test('тёмные темы и откат DESIGN2=0 — прежние цвета', () {
    for (final s in [style(Palette.depth), style(Palette.library), style(Palette.notebook, design2: false)]) {
      expect(s.darkInk, isFalse);
      for (final t in titles) {
        expect(s.ink(t), subjectColor(t));
      }
    }
  });
}
