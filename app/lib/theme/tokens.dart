// Собрано из design/tokens.json — tools/tokens.py; руками не править.
import 'package:flutter/painting.dart';

class ThemeDepth {
  static const bg = Color(0xFF141823);
  static const bgGlow1 = Color(0xFF2A3060);
  static const bgGlow2 = Color(0xFF1B3A3C);
  static const card = Color(0x13FFFFFF);
  static const cardSolid = Color(0xFF1F2331);
  static const line = Color(0x1AFFFFFF);
  static const text = Color(0xFFF3F4F8);
  static const muted = Color(0xFF9AA0B2);
  static const accent = Color(0xFF9FA6FF);
  static const onAccent = Color(0xFF141823);
  static const ok = Color(0xFF2FBF71);
  static const warn = Color(0xFFF5A524);
  static const danger = Color(0xFFFF6B6B);
  static const tabbar = Color(0xCC202434);
}

class ThemeNotebook {
  static const bg = Color(0xFFE9E3D8);
  static const bgGlow1 = Color(0xFFEBE4D8);
  static const bgGlow2 = Color(0xFFE4DDD0);
  static const card = Color(0xFFF3EEE5);
  static const cardSolid = Color(0xFFF3EEE5);
  static const line = Color(0xFFDBD3C4);
  static const text = Color(0xFF2A2721);
  static const muted = Color(0xFF7D776B);
  static const accent = Color(0xFFB75438);
  static const onAccent = Color(0xFFFFFFFF);
  static const ok = Color(0xFF5C8A4E);
  static const warn = Color(0xFFC98A1B);
  static const danger = Color(0xFFC4473A);
  static const tabbar = Color(0xDBF3EEE5);
}

const subjectColors = <Color>[
  Color(0xFF8B7CF6),
  Color(0xFFF5A524),
  Color(0xFF2EC4B6),
  Color(0xFFFF6B6B),
  Color(0xFF4F8CFF),
  Color(0xFFE86FB0),
  Color(0xFF7BC67E),
  Color(0xFFF2994A),
];

class Radii {
  static const double card = 26;
  static const double tile = 20;
  static const double chip = 14;
  static const double tabbar = 32;
  static const double pill = 999;
}

class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 18;
  static const double xl = 24;
  static const double xxl = 32;
}
