"""Иконки приложения на выбор (5.79, второй круг дизайна, Никита 12.10).

    python tools/app_icons.py            — пересобрать иконки вариантов
    python tools/app_icons.py --preview  — плюс app/build/app_icons.png (все рядом)

Капибара — маска позы «на мяче» (app/assets/capy/splash.png, та же, что на
нынешней иконке), композиция — как у неё: холст маски 82 % иконки по центру.
Нынешняя иконка («Как сейчас», ic_launcher и AppIcon) не меняется — по
умолчанию она. Остальные:

* Android — app/android/app/src/main/res/mipmap-*/ic_launcher_<имя>.png
  (обычные квадратные, как ic_launcher; alias в AndroidManifest.xml);
* iOS — app/ios/Runner/Assets.xcassets/Icon<Имя>.appiconset
  (альтернативные иконки: ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES
  в project.pbxproj, Info.plist собирает Xcode).

Имена — те же, что в app/lib/theme/app_icon.dart (AppIcon.*).
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
MASK = APP / "assets" / "capy" / "splash.png"
RES = APP / "android" / "app" / "src" / "main" / "res"
XCASSETS = APP / "ios" / "Runner" / "Assets.xcassets"

M = 2048             # холст отрисовки (потом — уменьшение, края гладкие)
CAPY = 0.8164        # холст маски 256 → 836 из 1024, как у нынешней иконки

# имя: (фон, капибара); фон — цвет или ("grad", угол CSS, [(цвет, доля)…])
VARIANTS = {
    "depth": ("#141823", "#FFFFFF"),
    "indigo": ("#5B5FE0", "#FFFFFF"),
    "terracotta": ("#B75438", "#F3EEE5"),
    "page": ("#F3EEE5", "#2A2721"),
    "sunset": (("grad", 160, [("#F2994A", 0.0), ("#B75438", 0.6), ("#5B3A8F", 1.0)]), "#FFFFFF"),
    "library": ("#111715", "#B9DCA3"),
}
PAGE_PAPER, PAGE_LINE = "#F3EEE5", "#B75438"

ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# (размер в точках, idiom, масштаб) — iPhone 120/180, iPad 152/167 и
# мелкие для «Настроек» и поиска (без них там была бы основная)
IOS = [
    ("20x20", "iphone", 2), ("20x20", "iphone", 3),
    ("29x29", "iphone", 2), ("29x29", "iphone", 3),
    ("40x40", "iphone", 2), ("40x40", "iphone", 3),
    ("60x60", "iphone", 2), ("60x60", "iphone", 3),
    ("20x20", "ipad", 2), ("29x29", "ipad", 2), ("40x40", "ipad", 2),
    ("76x76", "ipad", 2), ("83.5x83.5", "ipad", 2),
]


def rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def background(spec) -> Image.Image:
    if isinstance(spec, str):
        return Image.new("RGB", (M, M), rgb(spec))
    _, angle, stops = spec
    # как linear-gradient в CSS: 0° — вверх, 90° — вправо; длина линии —
    # чтобы углы квадрата попали ровно в 0 и 1
    a = math.radians(angle)
    dx, dy = math.sin(a), -math.cos(a)
    g = 256  # градиент гладкий: считаем мелко и растягиваем
    half = (abs(dx) + abs(dy)) * g / 2
    stops = [(rgb(c), t) for c, t in stops]
    img = Image.new("RGB", (g, g))
    px = img.load()
    lut = []
    for i in range(1024):
        t = i / 1023
        for (c0, t0), (c1, t1) in zip(stops, stops[1:]):
            if t <= t1:
                k = 0 if t1 == t0 else (t - t0) / (t1 - t0)
                lut.append(tuple(round(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)))
                break
    c = (g - 1) / 2
    for y in range(g):
        oy = (y - c) * dy
        for x in range(g):
            t = ((x - c) * dx + oy) / (2 * half) + 0.5
            px[x, y] = lut[min(1023, max(0, round(t * 1023)))]
    return img.resize((M, M), Image.BICUBIC)


def capy_mask(size: int, solid_below: int | None = None) -> Image.Image:
    """Альфа маски, растянутая до size и с чёткими краями (маска — 256 px).
    solid_below — с этой строки маски тело сплошное (мяч и лапы в «Из-за
    страницы» не просвечивают над краем листа); голову (x ≥ 186) не трогаем."""
    a = Image.open(MASK).convert("LA").split()[-1]
    if solid_below is not None:
        px = a.load()
        for y in range(solid_below, a.height):
            xs = [x for x in range(186) if px[x, y] >= 128]
            for x in range(xs[0], xs[-1] + 1) if xs else ():
                px[x, y] = 255
    a = a.resize((size, size), Image.BICUBIC)
    # «уровни»: размытый край после увеличения — снова резкий, но не ступенькой
    return a.point(lambda v: 0 if v < 96 else 255 if v > 160 else round((v - 96) * 255 / 64))


def render(name: str) -> Image.Image:
    bg, fg = VARIANTS[name]
    img = background(bg)
    if name == "page":
        # «из-за страницы»: капибара крупнее и ниже, низ закрывает лист
        # бумаги с терракотовой линией по краю — видна примерно половина
        size = round(M * 0.96)
        mask = capy_mask(size, solid_below=100)
        x, y = (M - size) // 2, round(M * 0.06)  # нос — чуть выше края листа
        img.paste(Image.new("RGB", (size, size), rgb(fg)), (x, y), mask)
        top = round(M * 0.60)
        d = ImageDraw.Draw(img)
        d.rectangle([0, top, M, M], fill=rgb(PAGE_PAPER))
        d.rectangle([0, top, M, top + round(M * 0.022)], fill=rgb(PAGE_LINE))
        return img.resize((1024, 1024), Image.LANCZOS)
    size = round(M * CAPY)
    mask = capy_mask(size)
    off = (M - size) // 2
    img.paste(Image.new("RGB", (size, size), rgb(fg)), (off, off), mask)
    return img.resize((1024, 1024), Image.LANCZOS)


def cap(name: str) -> str:
    return "Icon" + name[0].upper() + name[1:]


def save(img: Image.Image, px: int, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((px, px), Image.LANCZOS).save(path, optimize=True)


def build(preview: bool = False):
    shots = []
    for name in VARIANTS:
        big = render(name)
        shots.append(big)
        for dens, px in ANDROID.items():
            save(big, px, RES / f"mipmap-{dens}" / f"ic_launcher_{name}.png")
        folder = XCASSETS / f"{cap(name)}.appiconset"
        images = []
        for pt, idiom, scale in IOS:
            fn = f"{cap(name)}-{idiom}-{pt}@{scale}x.png"
            save(big, round(float(pt.split("x")[0]) * scale), folder / fn)
            images.append({"filename": fn, "idiom": idiom, "scale": f"{scale}x", "size": pt})
        folder.joinpath("Contents.json").write_text(
            json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
            encoding="utf-8",
        )
    if preview:
        cur = Image.open(XCASSETS / "AppIcon.appiconset" / "Icon-App-1024x1024@1x.png").convert("RGB")
        tiles = [cur] + shots
        sheet = Image.new("RGB", (len(tiles) * 280 + 20, 300), (200, 200, 200))
        for i, t in enumerate(tiles):
            sheet.paste(t.resize((260, 260), Image.LANCZOS), (20 + i * 280, 20))
        out = APP / "build" / "app_icons.png"
        out.parent.mkdir(exist_ok=True)
        sheet.save(out)
        print(out)


if __name__ == "__main__":
    build(preview="--preview" in sys.argv)
