"""Статистика для старосты (/stats): события без содержимого, картинка."""
import time

import aiosqlite
import pytest

import stats


def test_kind_for_paths():
    assert stats.kind_for("GET", "/api/me") == "open"
    assert stats.kind_for("GET", "/api/deadlines") == "deadlines"
    assert stats.kind_for("POST", "/api/files/12/link") == "download"
    assert stats.kind_for("POST", "/api/files/delete") is None        # удаление — не «скачал»
    assert stats.kind_for("POST", "/api/sdo/submit") == "submit"
    assert stats.kind_for("GET", "/api/sdo/grades/18672") == "sdo"
    assert stats.kind_for("GET", "/health") is None


@pytest.mark.asyncio
async def test_views_throttled_actions_not(db, monkeypatch):
    monkeypatch.setattr(stats, "_last", {})
    for _ in range(3):
        await stats.track(222, "open")       # просмотр — раз в 30 минут
        await stats.track(222, "ai")         # действие — каждое
    async with aiosqlite.connect(db.DATABASE_PATH) as con:
        rows = await (await con.execute("SELECT kind, COUNT(*) FROM events GROUP BY kind")).fetchall()
    assert dict(rows) == {"open": 1, "ai": 3}


@pytest.mark.asyncio
async def test_collect_and_render(db, monkeypatch):
    monkeypatch.setattr(stats, "_last", {})
    for uid in (1, 2, 3):
        await db.upsert_user(uid, "", "")
        await stats.track(uid, "open")
    await stats.track(1, "deadlines")
    await stats.track(2, "submit")
    s = await stats.collect(7)
    assert s["total"] == 3 and s["day"] == 3 and s["week"] == 3
    assert dict((label, n) for label, _, n in s["screens"])["Приложение"] == 3
    assert dict(s["actions"])["сдано работ"] == 1
    assert sum(map(sum, s["heat"])) == 5
    png = stats.render(s)
    assert png[:8] == b"\x89PNG\r\n\x1a\n" and len(png) > 10_000


@pytest.mark.asyncio
async def test_webapp_request_is_tracked(db, monkeypatch):
    from fastapi.testclient import TestClient
    import webapp.server as server
    from tests.test_webapp_home import BOT_TOKEN, _make_init_data
    monkeypatch.setattr(server, "BOT_TOKEN", BOT_TOKEN)
    monkeypatch.setattr(stats, "_last", {})
    c = TestClient(server.app)
    assert c.get("/api/me", headers={"X-Telegram-Init-Data": _make_init_data()}).status_code == 200
    async with aiosqlite.connect(db.DATABASE_PATH) as con:
        rows = await (await con.execute("SELECT user_id, kind FROM events")).fetchall()
    assert rows == [(222, "open")]


@pytest.mark.asyncio
async def test_stats_command_only_for_starosta(db, monkeypatch):
    from aiogram import Bot, Dispatcher
    from aiogram.fsm.storage.memory import MemoryStorage
    from aiogram.types import Chat, Message, Update, User
    from handlers import announce, deadlines
    from tests.conftest import STAROSTA_ID
    from tests.test_solver_render import RecordingSession

    class Session(RecordingSession):
        def __init__(self, *a, **kw):
            super().__init__(*a, **kw)
            self.photos = []

        async def make_request(self, bot, method, timeout=None):
            if type(method).__name__ == "SendPhoto":
                self.photos.append((method.chat_id, method.caption))
                return Message(message_id=5, date=0, chat=Chat(id=method.chat_id, type="private")).as_(bot)
            return await super().make_request(bot, method, timeout)

    bot = Bot(token="123456:TEST-TOKEN-NOT-REAL-AAAAAAAAAAAAAAAAAAA", session=Session())
    dp = Dispatcher(storage=MemoryStorage())
    dp.include_router(deadlines.router)   # как в handlers/__init__.py: раньше announce
    dp.include_router(announce.router)
    try:
        for i, uid in enumerate((222, STAROSTA_ID)):
            u = User(id=uid, is_bot=False, first_name="X")
            msg = Message(message_id=i + 1, date=0, chat=Chat(id=uid, type="private"), from_user=u, text="/stats")
            await dp.feed_update(bot, Update(update_id=int(time.time()) + i, message=msg))
    finally:
        announce.router._parent_router = None
        deadlines.router._parent_router = None
    assert [chat for chat, _ in bot.session.photos] == [STAROSTA_ID]
    # остальным /stats по-прежнему показывает их дедлайны
    assert any("Статистика дедлайнов" in text for text, _ in bot.session.sent)
    assert "Статистика за 30 дн." in bot.session.photos[0][1]
