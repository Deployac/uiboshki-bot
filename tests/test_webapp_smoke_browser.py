"""
Дымовой тест WebApp в настоящем Chromium: главная открывается на тестовой
базе без ошибок JS. Ловит то, что node-проверки (tests/test_webapp_static.py)
не видят: порядок скриптов, обращения к DOM при загрузке, сломанный запуск
из main.js. Telegram — заглушкой window.Telegram.WebApp (скрипт telegram.org
не грузим). Нет Playwright или Chromium (как в CI) — тест пропускается.
"""
import asyncio
import os
import socket

import pytest

from tests.test_webapp_auth import BOT_TOKEN, _make_init_data

CHROMIUM = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"

try:
    from playwright.sync_api import sync_playwright
except Exception:          # нет пакета — пропускаем
    sync_playwright = None

pytestmark = pytest.mark.skipif(sync_playwright is None or not os.path.exists(CHROMIUM),
                                reason="нужны Playwright и Chromium")

TG_STUB = """
window.Telegram = { WebApp: {
  initData: %s, initDataUnsafe: { user: { id: 222, first_name: "Alice" } },
  platform: "tdesktop", colorScheme: "dark", themeParams: {}, version: "7.0",
  isVersionAtLeast: () => false, ready() {}, expand() {}, setHeaderColor() {},
  onEvent() {}, offEvent() {}, openLink() {}, openTelegramLink() {},
  BackButton: { onClick() {}, offClick() {}, show() {}, hide() {} },
  HapticFeedback: { impactOccurred() {}, notificationOccurred() {} },
} };
"""


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _browse(url: str, init_data: str):
    """Открыть главную и пройтись по вкладкам; → (ошибки JS, текст карточки сверху).
    Браузер — в своём потоке: у цикла теста запуск подпроцессов не работает."""
    import json
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROMIUM)
        page = browser.new_page(viewport={"width": 390, "height": 844})
        page.on("pageerror", lambda e: errors.append(str(e)))
        # 4xx/5xx API (СДО не подключён и т.п.) Chromium тоже пишет в консоль — это не ошибки JS
        page.on("console", lambda m: m.type == "error" and "Failed to load resource" not in m.text
                and errors.append(m.text))
        page.route("https://telegram.org/**", lambda route: route.abort())
        page.add_init_script(TG_STUB % json.dumps(init_data))
        page.goto(url)
        page.wait_for_function("document.querySelectorAll('#daychips button').length === 6")
        page.wait_for_function("document.getElementById('hero').textContent.includes('Повторить')")
        hero = page.inner_text("#hero")
        page.evaluate("document.getElementById('onboard').classList.remove('open')")   # знакомство не мешает
        for tab in ("search", "chat", "sdo", "today"):
            page.click(f"nav.tabs button[data-tab='{tab}']")
        page.wait_for_timeout(300)
        browser.close()
    return errors, hero


@pytest.mark.asyncio
async def test_home_opens_without_js_errors(db, monkeypatch):
    import bot
    import handlers.weather
    import schedule_parser
    import webapp.deps as deps

    async def mirea_down(*a, **k):
        raise RuntimeError("МИРЭА не отвечает")

    async def no_weather(*a, **k):
        return ""

    monkeypatch.setattr(deps, "BOT_TOKEN", BOT_TOKEN)
    import config
    await db.upsert_user(222, "", "Alice")
    await db.set_user_group(222, config.HOME_GROUP_ID)          # группа уже выбрана — лист выбора не мешает
    monkeypatch.setattr(schedule_parser, "fetch_schedule_raw", mirea_down)
    monkeypatch.setattr(handlers.weather, "get_weather_for_morning", no_weather)
    port = _free_port()
    server, task = bot.start_webapp(port)
    try:
        for _ in range(50):
            if server.started:
                break
            await asyncio.sleep(0.1)
        errors, hero = await asyncio.to_thread(_browse, f"http://127.0.0.1:{port}/", _make_init_data())
        assert not errors, errors
        assert "НЕ ЗАГРУЗИЛОСЬ" in hero.upper() and "Повторить" in hero     # МИРЭА лежит — так и пишем
    finally:
        await bot.stop_webapp(server, task)


def _landing(url: str) -> str:
    """Корень в обычном браузере (initData пустой) → адрес, где оказались."""
    import json
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROMIUM)
        page = browser.new_page()
        page.route("https://telegram.org/**", lambda route: route.abort())
        page.add_init_script(TG_STUB % json.dumps(""))
        page.goto(url)
        page.wait_for_url("**/about")
        final = page.url
        browser.close()
    return final


@pytest.mark.asyncio
async def test_root_in_plain_browser_goes_to_site(db, monkeypatch):
    """www.uiboshki.ru вне Telegram — сайт /about, а не приложение без входа."""
    import bot
    port = _free_port()
    server, task = bot.start_webapp(port)
    try:
        for _ in range(50):
            if server.started:
                break
            await asyncio.sleep(0.1)
        final = await asyncio.to_thread(_landing, f"http://127.0.0.1:{port}/")
        assert final.endswith("/about")
    finally:
        await bot.stop_webapp(server, task)
