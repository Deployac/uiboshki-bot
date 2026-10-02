"""Заголовки безопасности, ограничение размера запроса, лимиты частоты."""
import pytest


@pytest.fixture
def client(db, monkeypatch):
    from fastapi.testclient import TestClient
    import ratelimit
    import webapp.server as server
    from tests.test_webapp_home import BOT_TOKEN, _make_init_data
    monkeypatch.setattr(server, "BOT_TOKEN", BOT_TOKEN)
    ratelimit.reset()
    return TestClient(server.app), {"X-Telegram-Init-Data": _make_init_data()}


def test_headers(client):
    c, h = client
    r = c.get("/api/me", headers=h)
    assert r.headers["X-Content-Type-Options"] == "nosniff"
    assert r.headers["Referrer-Policy"] == "no-referrer"
    assert r.headers["Cache-Control"] == "no-store"
    health = c.get("/health")
    assert health.headers["X-Content-Type-Options"] == "nosniff" and health.headers.get("Cache-Control") != "no-store"


def test_body_limits(client):
    c, h = client
    big = "x" * (2 * 1024 * 1024)
    r = c.post("/api/deadlines", content='{"subject": "' + big + '"}', headers={**h, "Content-Type": "application/json"})
    assert r.status_code == 413
    # сдаче работ можно больше
    r = c.post("/api/sdo/submit", content='{"files": "' + big + '"}', headers={**h, "Content-Type": "application/json"})
    assert r.status_code != 413


def test_deadline_rate_limit(client):
    c, h = client
    codes = [c.post("/api/deadlines", json={"subject": f"д{i}", "due_date": "2099-01-01"}, headers=h).status_code
             for i in range(21)]
    assert codes[:20] == [200] * 20 and codes[20] == 429


def test_cors_only_own_origin(monkeypatch):
    import webapp.server as server
    monkeypatch.setattr(server, "WEBAPP_URL", "https://uiboshki-bot-production.up.railway.app/app?x=1")
    assert server._allowed_origins() == ["https://uiboshki-bot-production.up.railway.app"]
    monkeypatch.setattr(server, "WEBAPP_URL", "")
    assert server._allowed_origins() == ["*"]


def test_httpx_urls_not_logged():
    import logging
    import webapp.server  # noqa: F401 — настраивает логи
    assert logging.getLogger("httpx").level >= logging.WARNING
