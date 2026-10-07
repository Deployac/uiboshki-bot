"""Дизайн-токены (design/tokens.json) → CSS-переменные для WebApp/PWA и
Dart-константы для своего приложения на Flutter.

    python tools/tokens.py            — пересобрать webapp/static/tokens.css (и app/…/tokens.dart, если есть app/)

Тест tests/test_design_tokens.py следит, что tokens.css собран из текущего
tokens.json. Сами экраны WebApp пока на своих цветах (app.css); токены —
общий словарь дизайна для приложения (этап 3) и новых экранов."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKENS = ROOT / "design" / "tokens.json"
CSS = ROOT / "webapp" / "static" / "tokens.css"
DART = ROOT / "app" / "lib" / "theme" / "tokens.dart"


def load() -> dict:
    return json.loads(TOKENS.read_text(encoding="utf-8"))


def css(t: dict) -> str:
    out = ["/* Собрано из design/tokens.json — tools/tokens.py; руками не править. */"]
    for name, theme in t["themes"].items():
        out.append(f'[data-app-theme="{name}"] {{')
        out += [f"  --t-{k.replace('_', '-')}: {v};" for k, v in theme.items() if k != "label"]
        out.append("}")
    out.append(":root {")
    out += [f"  --t-subject-{i}: {c};" for i, c in enumerate(t["subjects"])]
    out += [f"  --t-radius-{k}: {v}px;" for k, v in t["radius"].items()]
    out += [f"  --t-space-{k}: {v}px;" for k, v in t["space"].items()]
    out.append("}")
    return "\n".join(out) + "\n"


def _argb(hex_color: str) -> str:
    h = hex_color.lstrip("#").upper()
    rgb, a = (h[:6], h[6:8] or "FF")
    return f"0x{a}{rgb}"


def dart(t: dict) -> str:
    lines = ["// Собрано из design/tokens.json — tools/tokens.py; руками не править.",
             "import 'package:flutter/painting.dart';", ""]
    for name, theme in t["themes"].items():
        cls = "Theme" + name.capitalize()
        lines.append(f"class {cls} {{")
        for k, v in theme.items():
            if k == "label":
                continue
            camel = k.split("_")[0] + "".join(p.capitalize() for p in k.split("_")[1:])
            lines.append(f"  static const {camel} = Color({_argb(v)});")
        lines += ["}", ""]
    lines.append("const subjectColors = <Color>[" + ", ".join(f"Color({_argb(c)})" for c in t["subjects"]) + "];")
    lines += ["", "class Radii {"] + [f"  static const double {k} = {v};" for k, v in t["radius"].items()] + ["}"]
    lines += ["", "class Space {"] + [f"  static const double {k} = {v};" for k, v in t["space"].items()] + ["}"]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    t = load()
    CSS.write_text(css(t), encoding="utf-8")
    print(f"→ {CSS.relative_to(ROOT)}")
    if DART.parent.parent.parent.exists():
        DART.parent.mkdir(parents=True, exist_ok=True)
        DART.write_text(dart(t), encoding="utf-8")
        print(f"→ {DART.relative_to(ROOT)}")
