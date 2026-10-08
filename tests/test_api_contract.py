"""Этап 2 (в): API как контракт — снимок путей, /api/v1, /api/meta."""
import json
from pathlib import Path

from fastapi.testclient import TestClient

SNAPSHOT = Path(__file__).parent / "api_contract.json"


def test_api_matches_snapshot():
    """Пропал путь — старые версии приложения в магазинах сломаются; новый —
    добавь в контракт осознанно: python tools/api_snapshot.py"""
    from tools.api_snapshot import routes
    saved, live = set(json.loads(SNAPSHOT.read_text(encoding="utf-8"))), set(routes())
    assert not saved - live, f"из API пропало: {sorted(saved - live)}"
    assert not live - saved, f"новое в API — обнови снимок (tools/api_snapshot.py): {sorted(live - saved)}"


def test_v1_prefix_and_meta(db, monkeypatch):
    import webapp.server as server
    from tests.test_webapp_home import BOT_TOKEN, _make_init_data
    monkeypatch.setattr(server.deps, "BOT_TOKEN", BOT_TOKEN)
    c = TestClient(server.app)
    meta = c.get("/api/v1/meta").json()
    assert meta["api"] == 1 and meta["server"].count(".") == 2 and set(meta["min_client"]) == {"web", "android", "ios"}
    h = {"X-Telegram-Init-Data": _make_init_data()}
    assert c.get("/api/v1/me", headers=h).json()["id"] == c.get("/api/me", headers=h).json()["id"]
    assert c.get("/api/v1/me").status_code == 401                              # вход — как у /api
    monkeypatch.setenv("APP_MIN_IOS", "1.2.0")
    assert c.get("/api/meta").json()["min_client"]["ios"] == "1.2.0"
