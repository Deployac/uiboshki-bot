"""
Интерфейс WebApp без браузера: index.html разбит на app.css и js/*.js (по
вкладкам), и ошибка в любом из них ломает приложение целиком — у всех и
сразу. Раньше это ловилось только скриншотами. Здесь дешёвые проверки,
которые гоняются в CI: синтаксис JS, что всё подключено и отдаётся, что
id и onclick из разметки существуют, что части не объявляют одно и то же.
"""
import re
import shutil
import subprocess
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

STATIC = Path(__file__).resolve().parent.parent / "webapp" / "static"
HTML = (STATIC / "index.html").read_text(encoding="utf-8")
JS_FILES = re.findall(r'<script src="(js/[\w-]+\.js)"></script>', HTML)
JS = {name: (STATIC / name).read_text(encoding="utf-8") for name in JS_FILES}
ALL_JS = "\n".join(JS.values())


def test_all_parts_are_wired_in_order():
    assert JS_FILES[0] == "js/core.js" and JS_FILES[-1] == "js/main.js"
    assert sorted(JS_FILES) == sorted(f"js/{p.name}" for p in (STATIC / "js").glob("*.js"))
    assert '<link rel="stylesheet" href="app.css">' in HTML
    assert "<script>" not in HTML and "<style>" not in HTML      # больше ничего не встроено


@pytest.mark.skipif(not shutil.which("node"), reason="нужен node")
@pytest.mark.parametrize("name", JS_FILES)
def test_js_syntax(name):
    res = subprocess.run(["node", "--check", str(STATIC / name)], capture_output=True, text=True)
    assert res.returncode == 0, res.stderr


def test_index_versions_assets_and_they_are_served():
    import webapp.server as server
    client = TestClient(server.app)
    page = client.get("/")
    assert page.status_code == 200 and page.headers["cache-control"] == "no-cache"
    urls = re.findall(r'(?:src|href)="((?:js/[\w-]+\.js|app\.css)\?v=[0-9a-f]{10})"', page.text)
    assert len(urls) == len(JS_FILES) + 1
    for url in urls:
        assert client.get("/" + url).status_code == 200


def test_ids_used_in_js_exist():
    ids_in_html = set(re.findall(r'\bid="([\w-]+)"', HTML))
    ids_made_by_js = set(re.findall(r'\bid=\\?"([\w-]+)\\?"', ALL_JS)) | set(re.findall(r'\.id\s*=\s*"([\w-]+)"', ALL_JS))
    used = set(re.findall(r'getElementById\("([\w-]+)"\)', ALL_JS))
    used |= set(re.findall(r'querySelector(?:All)?\("#([\w-]+)', ALL_JS))
    missing = used - ids_in_html - ids_made_by_js
    assert not missing, f"в разметке нет элементов: {sorted(missing)}"


def test_onclick_handlers_are_defined():
    defined = set(re.findall(r'^(?:async\s+)?function\s+(\w+)\s*\(', ALL_JS, re.M))
    called = set(re.findall(r'onclick="(\w+)\(', HTML))
    assert called - defined == set(), f"нет функций: {sorted(called - defined)}"


def test_no_part_redeclares_anothers_globals():
    seen = {}
    for name, text in JS.items():
        for kind, ident in re.findall(r'^(?:async\s+)?(function|const|let|var)\s+(\w+)', text, re.M):
            assert ident not in seen, f"{ident} объявлен и в {seen[ident]}, и в {name}"
            seen[ident] = name


def test_sdo_pips_fill_from_left():
    # живой скрин 01.10: «1 из 4 закрыто» подсвечивало последнее деление (закрытые карточки идут в конце)
    assert "i < closed" in JS["js/sdo.js"]


def test_icons_used_are_drawn():
    # свои иконки (js/icons.js) вместо эмодзи: каждая, что зовётся из JS или
    # разметки, нарисована — иначе на её месте пустое место
    drawn = set(re.findall(r"^\s+(\w+): '", JS["js/icons.js"], re.M))
    drawn |= set(re.findall(r'<symbol id="i-(\w+)"', JS["js/icons.js"]))     # отдельные символы (капибара)
    used = set(re.findall(r'icon\("(\w+)"', ALL_JS)) | set(re.findall(r'href="#i-(\w+)"', HTML))
    look = JS["js/sdo.js"].split("const WORK_LOOK = {", 1)[1].split("};", 1)[0]
    used |= set(re.findall(r'\["(\w+)", "', look))
    cats = JS["js/files.js"].split("const CAT_ICONS = {", 1)[1].split("};", 1)[0]
    used |= set(re.findall(r': "(\w+)"', cats))
    missing = {u for u in used if u not in drawn and u not in ("ok", "bad", "warn", "")}
    assert not missing, f"не нарисованы: {sorted(missing)}"


def test_tab_bar_and_menu_use_own_icons():
    nav = HTML[HTML.index('<nav class="tabs">'):HTML.index("</nav>")]
    menu = HTML[HTML.index('id="more-menu"'):HTML.index('id="sdo-sheet"')]
    emoji = re.compile("[\U0001F300-\U0001FAFF☀-➿]")
    assert not emoji.search(nav) and not emoji.search(menu)


def test_theme_follows_telegram_live():
    # тема Telegram меняется без перезапуска приложения — перекрашиваемся сразу
    core = JS["js/core.js"]
    assert 'tg.onEvent("themeChanged", applyTheme)' in core
    assert "dataset.theme" in core
    css = (STATIC / "app.css").read_text(encoding="utf-8")
    assert ':root[data-theme="light"]' in css and "var(--switch-off)" in css


def test_onboarding_once_and_not_on_deep_links():
    more, main = JS["js/more.js"], JS["js/main.js"]
    assert "CloudStorage" in more and "onboarded_v1" in more        # один раз, и на другом телефоне тоже
    assert "if (!deepLink) maybeOnboard();" in main                 # из уведомления — без знакомства
    assert 'id="onboard"' in HTML


def test_happy_empty_states_with_capybara():
    assert "function capyEmpty(" in JS["js/core.js"]
    for f in ("js/deadlines.js", "js/home.js", "js/files.js", "js/sdo.js", "js/search.js"):
        assert "capyEmpty(" in JS[f], f


def test_telegram_back_closes_sheets_first():
    main = JS["js/main.js"]
    assert "closeTopSheet" in main and "MutationObserver" in main
    assert "NESTED().forEach(fn => tg.BackButton.offClick(fn))" in main     # без двойного «назад»


def test_whats_new_once_per_release():
    more = JS["js/more.js"]
    assert "const NEWS = {" in more and 'cloudFlag("news_seen", NEWS.id)' in more
    assert "if (firstVisit) { cloudFlag(\"news_seen\", NEWS.id); return; }" in more   # новичку — только знакомство
    assert 'id="news-sheet"' in HTML


def test_home_starts_instantly_from_saved_day():
    # Мгновенный старт: сводка «сегодня» за этот же день — из памяти телефона,
    # свежая — следом; имя — сразу из Telegram; пары сегодня — без /api/day.
    home = JS["js/home.js"]
    assert "readHomeSnap()" in home and "saveHomeSnap()" in home
    assert "snap.today.date === isoDate(new Date())" in home          # только за сегодня
    assert "tg.initDataUnsafe.user" in home
    assert "renderDay(list, todayData)" in home


# ── Дизайн-ревью, пункты 1–5 (v5.5.0) ──────────────────────────────────────

CSS = (STATIC / "app.css").read_text(encoding="utf-8")


def test_chat_opens_at_last_message():
    # п. 1: чат с историей открывался сверху, на самых старых сообщениях
    assert "scrollChatToEnd()" in JS["js/core.js"].split("function switchTab")[1].split("\n}\n")[0]
    chat = JS["js/chat.js"]
    assert "function scrollChatToEnd()" in chat and "if (!chatLog.length) return;" in chat


def test_security_says_starosta_sees_who():
    # п. 2: с v5.1.0 староста видит в /stats, кто пользуется, — экран «Безопасность» говорит об этом
    assert "Староста видит, кто именно" in JS["js/more.js"]


def test_light_theme_text_is_darker():
    # п. 3: в светлой теме зелёные/оранжевые надписи читались плохо — тексту свои цвета
    assert not re.search(r"(?<![-\w])color: var\(--(ok|warn|accent-2|danger)\)", CSS)
    light = CSS.split(':root[data-theme="light"] { --switch-off')[1].split("}")[0]
    for var in ("--ok-text", "--warn-text", "--accent-2-text", "--danger-text"):
        assert var in light


def test_sdo_legend_lists_every_colour_in_bars():
    # п. 4: в полосках пять цветов, в легенде было три
    sdo = JS["js/sdo.js"]
    assert "legendHtml(list)" in sdo and '"трудовая деятельность"' in sdo and '"достижения"' in sdo


def test_search_filters_stay_in_one_row():
    # п. 5: «Аудитории» на узком iPhone уезжали на вторую строку
    assert re.search(r"#target-types \{ flex-wrap: nowrap; overflow-x: auto;", CSS)
