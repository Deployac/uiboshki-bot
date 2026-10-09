"""Этап 2: вход в приложение без Telegram — код входа, подтверждение в
боте, токен сессии устройства, список устройств и выход."""
import time

import pytest
from aiogram import Bot, Dispatcher
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import CallbackQuery, Chat, Message, Update, User
from fastapi.testclient import TestClient

from tests.test_deadlines_routing import FakeSession

UID = 777


async def _bot_says(dp, bot, text=None, data=None):
    user = User(id=UID, is_bot=False, first_name="Аня")
    msg = Message(message_id=1, date=0, chat=Chat(id=UID, type="private"), from_user=user, text=text or "x")
    if data:
        upd = Update(update_id=int(time.time() * 1000) % 10**9,
                     callback_query=CallbackQuery(id="1", from_user=user, chat_instance="c", data=data, message=msg))
    else:
        upd = Update(update_id=int(time.time() * 1000) % 10**9, message=msg)
    await dp.feed_update(bot, upd)


@pytest.fixture
def client(db, monkeypatch):
    import webapp.server as server
    from tests.test_webapp_home import BOT_TOKEN
    monkeypatch.setattr(server.deps, "BOT_TOKEN", BOT_TOKEN)
    return TestClient(server.app, headers={"User-Agent": "Mozilla/5.0 (Linux; Android 14) Chrome/130"})


@pytest.mark.asyncio
async def test_login_via_bot_gives_device_session(db, client):
    import handlers.start as start
    await db.upsert_user(UID, "anya", "Аня Петрова")
    res = client.post("/api/auth/start").json()
    code = res["code"]
    assert res["link"].endswith(f"?start=login_{code}")
    assert client.post("/api/auth/poll", json={"code": code}).json() == {"status": "wait"}

    bot = Bot(token="123456:TEST-TOKEN-NOT-REAL-AAAAAAAAAAAAAAAAAAA", session=FakeSession())
    dp = Dispatcher(storage=MemoryStorage())
    dp.include_router(start.router)
    try:
        await _bot_says(dp, bot, text=f"/start login_{code}")
        assert "Chrome · Android" in bot.session.sent_texts[-1][1]           # видно, что за устройство
        await _bot_says(dp, bot, data=f"login:ok:{code}")
    finally:
        start.router._parent_router = None

    ok = client.post("/api/auth/poll", json={"code": code}).json()
    assert ok["status"] == "ok" and ok["user_id"] == UID
    assert client.post("/api/auth/poll", json={"code": code}).json()["status"] == "expired"   # код — один раз
    h = {"Authorization": f"Bearer {ok['token']}"}
    me = client.get("/api/me", headers=h).json()
    assert me["id"] == UID and me["first_name"] == "Аня"
    devices = client.get("/api/auth/sessions", headers=h).json()["items"]
    assert len(devices) == 1 and devices[0]["current"] and devices[0]["device"] == "Chrome · Android"
    assert client.post("/api/auth/logout", headers=h).json()["revoked"] == 1
    assert client.get("/api/me", headers=h).status_code == 401              # вышел — токен не работает
    assert client.get("/api/me", headers={"Authorization": "Bearer someone-else"}).status_code == 401


@pytest.mark.asyncio
async def test_denied_and_expired(db, client):
    from database.sessions import decide_login
    code = client.post("/api/auth/start").json()["code"]
    assert await decide_login(code, UID, False)
    assert client.post("/api/auth/poll", json={"code": code}).json() == {"status": "denied"}
    assert not await decide_login(code, UID, True)                             # решение не переигрывается
    assert client.post("/api/auth/poll", json={"code": "нет-такого"}).json() == {"status": "expired"}


@pytest.mark.asyncio
async def test_logout_everywhere(db, client):
    from database.sessions import create_session
    await db.upsert_user(UID, "", "Аня")
    t1, t2 = await create_session(UID, "Phone"), await create_session(UID, "Laptop")
    h1 = {"Authorization": f"Bearer {t1}"}
    assert len(client.get("/api/auth/sessions", headers=h1).json()["items"]) == 2
    assert client.post("/api/auth/logout?everywhere=true", headers=h1).json()["revoked"] == 2
    assert client.get("/api/me", headers={"Authorization": f"Bearer {t2}"}).status_code == 401


@pytest.mark.asyncio
async def test_app_login_names_device(db, client):
    """Вход из своего приложения: у Dart нет браузера в User-Agent — бот спрашивал
    «на устройстве Браузер»; приложение шлёт X-App, и устройство — «Капибара · iPhone»."""
    from database.sessions import get_login
    res = client.post("/api/auth/start", headers={"User-Agent": "Dart/3.9 (dart:io)", "X-App": "ios"}).json()
    assert (await get_login(res["code"]))["device"] == "Капибара · iPhone"
    res = client.post("/api/auth/start", headers={"User-Agent": "Dart/3.9 (dart:io)", "X-App": "android"}).json()
    assert (await get_login(res["code"]))["device"] == "Капибара · Android"
