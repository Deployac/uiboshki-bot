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


def _pwa(url: str, token: str, standalone: bool = False) -> tuple[bool, bool, list]:
    """/app вне Telegram: (экран «Войти» открыт, главная загрузилась, ошибки JS).
    standalone — как с экрана «Домой» на iPhone; тогда вместо главной — отступ шапки сверху."""
    import json
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROMIUM)
        page = browser.new_page(viewport={"width": 390, "height": 844})
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.route("https://telegram.org/**", lambda route: route.abort())
        page.add_init_script(TG_STUB % json.dumps(""))
        if token:
            page.add_init_script(f"localStorage.setItem('uib_token', {json.dumps(token)})")
        if standalone:
            page.add_init_script("Object.defineProperty(navigator, 'standalone', { get: () => true })")
        page.goto(url)
        page.wait_for_timeout(800)
        login = page.evaluate("document.getElementById('login').classList.contains('open')")
        home = page.evaluate("document.getElementById('greeting') ? document.getElementById('greeting').textContent : ''")
        if standalone:
            home = page.evaluate("parseFloat(getComputedStyle(document.querySelector('header.top')).paddingTop)")
        browser.close()
    return login, (home if standalone else bool(home)), errors


@pytest.mark.asyncio
async def test_pwa_login_screen_and_token(db, monkeypatch):
    """Этап 2: /app вне Telegram — без входа «Войти через Telegram», с токеном — приложение."""
    import bot
    import webapp.deps as deps
    from database.sessions import create_session
    monkeypatch.setattr(deps, "BOT_TOKEN", BOT_TOKEN)
    await db.upsert_user(222, "", "Alice")
    token = await create_session(222, "test")
    port = _free_port()
    server, task = bot.start_webapp(port)
    try:
        for _ in range(50):
            if server.started:
                break
            await asyncio.sleep(0.1)
        login, _, errors = await asyncio.to_thread(_pwa, f"http://127.0.0.1:{port}/app", "")
        assert login and not errors, errors
        login, _, errors = await asyncio.to_thread(_pwa, f"http://127.0.0.1:{port}/app", token)
        assert not login and not errors, errors
    finally:
        await bot.stop_webapp(server, task)


@pytest.mark.asyncio
async def test_pwa_home_screen_header_below_clock(db, monkeypatch):
    """Баг (скрин владельца, iPhone 16 Pro): PWA с экрана «Домой» — шапка под часами.
    В режиме standalone шапка отступает как в полном экране Telegram (не меньше 44 + 8)."""
    import bot
    import webapp.deps as deps
    from database.sessions import create_session
    monkeypatch.setattr(deps, "BOT_TOKEN", BOT_TOKEN)
    await db.upsert_user(222, "", "Alice")
    token = await create_session(222, "test")
    port = _free_port()
    server, task = bot.start_webapp(port)
    try:
        for _ in range(50):
            if server.started:
                break
            await asyncio.sleep(0.1)
        _, top, errors = await asyncio.to_thread(_pwa, f"http://127.0.0.1:{port}/app", token, True)
        assert not errors, errors
        assert top >= 52
        _, home, _ = await asyncio.to_thread(_pwa, f"http://127.0.0.1:{port}/app", token)
        assert home
    finally:
        await bot.stop_webapp(server, task)


# ── Ночь 09.10: сайт ──
SITE_FIO = "Константинопольский-Великорецкий Александр Владимирович"


def _site_layout(url: str, width: int) -> dict:
    """/about на узком экране: поиск с длинными названиями и расписание преподавателя."""
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROMIUM)
        page = browser.new_page(viewport={"width": width, "height": 800})
        page.goto(url + "/about")
        page.fill("#schedule-query", "иванов")
        page.wait_for_selector(".search-results button")
        page.click(".search-results button[data-i='1']")
        page.wait_for_selector(".schedule-heading h3")
        res = page.evaluate("""() => {
          const r = (q) => document.querySelector(q).getBoundingClientRect();
          const ph = r('.phone'), ex = r('.demo-expand');
          // слово заголовка (до пробела или дефиса) не рвётся на две строки: один прямоугольник
          const t = document.querySelector('.schedule-heading h3').firstChild, words = [];
          for (const m of t.textContent.matchAll(/[^\\s-]+/g)) {
            const rg = document.createRange(); rg.setStart(t, m.index); rg.setEnd(t, m.index + m[0].length);
            words.push([m[0], rg.getClientRects().length]);
          }
          return {scroll: document.documentElement.scrollWidth, inner: innerWidth, words,
                  expandUnderPhone: ex.left < ph.right && ex.right > ph.left && ex.top < ph.bottom && ex.bottom > ph.top};
        }""")
        browser.close()
    return res


@pytest.mark.asyncio
async def test_site_narrow_layout(db, monkeypatch):
    """Баги сайта на узком экране: длинное название в поиске давало прокрутку
    вбок, кнопка «демо в отдельной вкладке» пряталась под телефоном, фамилия в
    заголовке расписания рвалась посреди слова."""
    import bot
    import ratelimit
    import schedule_index
    import webapp.routes.schedule as sched

    async def search(q="", type=0, user=None):
        return {"items": [{"type": 1, "id": 1, "title": "УИБО-03-24", "hint": "Группа"},
                          {"type": 2, "id": 2, "title": SITE_FIO, "hint": "Преподаватель"},
                          {"type": 1, "id": 3, "title": "ОченьДлинноеНазваниеБезПробелов" * 2, "hint": "Группа"}]}

    async def target(t, i, user=None):
        return {"type": t, "id": i, "title": SITE_FIO, "today": "2026-10-09", "stale": False, "weeks": []}

    async def ready():
        return False

    monkeypatch.setattr(sched, "api_search", search)
    monkeypatch.setattr(sched, "api_target", target)
    monkeypatch.setattr(schedule_index, "is_ready", ready)
    ratelimit.reset()
    port = _free_port()
    server, task = bot.start_webapp(port)
    try:
        for _ in range(50):
            if server.started:
                break
            await asyncio.sleep(0.1)
        for width in (320, 375, 700):
            res = await asyncio.to_thread(_site_layout, f"http://127.0.0.1:{port}", width)
            assert res["scroll"] <= res["inner"], (width, res)
            assert not res["expandUnderPhone"], width
            if width < 700:
                assert all(n == 1 for _, n in res["words"]), (width, res["words"])
    finally:
        await bot.stop_webapp(server, task)
        ratelimit.reset()
