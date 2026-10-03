"""Сайт-презентация /about (webapp/routes/site.py): страница, приложение в
демо-режиме (без SDK Telegram, на записанных тестовых данных) и живой поиск
расписания МИРЭА без входа — с ограничением частоты по IP."""
import json
import subprocess
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

SITE = Path(__file__).parent.parent / "webapp" / "static" / "site"


def _client():
    import webapp.server as server
    return TestClient(server.app)


def test_about_page_and_demo():
    c = _client()
    r = c.get("/about")
    assert r.status_code == 200 and "УИБО-бот" in r.text and 'src="/about/demo"' in r.text
    demo = c.get("/about/demo").text
    assert '<base href="/">' in demo and "site/demo.js?v=" in demo
    assert "telegram.org/js/telegram-web-app.js" not in demo                 # без настоящего SDK
    assert demo.index("site/demo.js") < demo.index("js/core.js")              # заглушка — до приложения
    for f in ("site/site.css", "site/site.js", "site/demo.js", "site/demo.json", "site/fonts/serif-cyrillic.woff2"):
        assert c.get("/" + f).status_code == 200, f


def test_site_scripts_parse_and_demo_data_is_complete():
    for f in ("site.js", "demo.js"):
        subprocess.run(["node", "--check", str(SITE / f)], check=True)
    # iOS: в iframe прокручивается body внутри экрана фиксированной высоты, а не
    # окно — иначе на коротком дне нижняя панель уезжала вверх (живой тест 04.10)
    demo = (SITE / "demo.js").read_text(encoding="utf-8")
    assert "html{height:100%;overflow:hidden}" in demo and "body{height:100%;overflow-y:auto" in demo
    assert "window.scrollTo = function" in demo and '"scrollY"' in demo
    fx = json.loads((SITE / "demo.json").read_text(encoding="utf-8"))["fx"]
    # то, что приложение спрашивает при открытии, есть в записи
    for key in ("GET /api/me", "GET /api/today", "GET /api/deadlines", "GET /api/files", "GET /api/sdo/grades",
                "GET /api/sdo/status", "POST /api/chat"):
        assert key in fx, key
    assert fx["GET /api/optional"]["pending"] == []                           # без вопроса про военку поверх главной
    course = fx["GET /api/sdo/grades"]["courses"][0]["id"]
    assert fx[f"GET /api/sdo/grades/{course}"]["goal"]["tk"]
    # ссылки на картинки слайдов из ответа ИИ — существуют
    for k, v in fx.items():
        if k.startswith("GET /api/files/") and "/page/" in k:
            assert (SITE.parent / v["image"]).exists(), v["image"]


@pytest.mark.asyncio
async def test_public_search_and_target(db, monkeypatch):
    import ratelimit
    import schedule_index
    import webapp.routes.schedule as sched

    async def search(q, types, limit=30):
        return [{"id": 4928, "title": "УИБО-03-24", "type": 1}]

    async def ready():
        return True

    async def target(target_type, target_id, user):
        assert user == {"id": 0}
        return {"type": 1, "id": 4928, "title": "УИБО-03-24", "pinned": False, "today": "2026-10-08",
                "weeks": [{"days": []}] * 8, "stale": None}

    monkeypatch.setattr(schedule_index, "search", search)
    monkeypatch.setattr(schedule_index, "is_ready", ready)
    monkeypatch.setattr(sched, "api_target", target)
    ratelimit.reset()
    c = _client()
    r = c.get("/about/api/search?q=УИБО")
    assert r.status_code == 200 and r.json()["items"][0]["id"] == 4928      # без initData
    t = c.get("/about/api/target/1/4928").json()
    assert "pinned" not in t and len(t["weeks"]) == 2
    codes = [c.get("/about/api/target/1/4928", headers={"X-Forwarded-For": "1.2.3.4"}).status_code for _ in range(16)]
    assert codes[:15] == [200] * 15 and codes[15] == 429                       # по IP
    assert c.get("/about/api/target/1/4928", headers={"X-Forwarded-For": "5.6.7.8"}).status_code == 200
    ratelimit.reset()
