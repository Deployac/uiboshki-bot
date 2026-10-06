"""Картинка превью ссылки на сайт /about: webapp/static/site/og.jpg (1200×630).

Сервер с WebApp должен быть запущен (стенд или локально):
    python tools/site_og.py http://localhost:8766
(свой Chromium — переменная CHROMIUM=/путь/к/chrome).
Страница — tools/site_og.html (стили сайта и живое демо в телефоне).
"""
import os
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent


def main(base: str):
    html = (ROOT / "tools" / "site_og.html").read_text(encoding="utf-8")
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path=os.environ.get("CHROMIUM") or None)   # своя сборка — CHROMIUM=…
        pg = b.new_page(viewport={"width": 1200, "height": 630})
        pg.goto(base.rstrip("/") + "/about", wait_until="networkidle")
        pg.set_content(html, wait_until="networkidle")
        pg.wait_for_timeout(3000)                     # демо в iframe дорисовывает главную
        pg.screenshot(path=str(ROOT / "webapp/static/site/og.jpg"), type="jpeg", quality=88)
        b.close()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8766")
