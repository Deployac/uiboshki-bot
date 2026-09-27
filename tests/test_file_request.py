"""Файл по запросу в чате и «📥 Скачать» в WebApp."""
import time

import pytest
from aiogram import Bot, Dispatcher
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import Chat, Message, Update

import file_request
from tests.test_deeplinks import USER, DocSession

OPD = "Основы предпринимательской деятельности"
UCH = "Учетная деятельность на предприятии"
AD = "Анализ данных"
FILES = [{"id": i, "subject": s, "title": t, "category": c} for i, (s, t, c) in enumerate([
    (OPD, "Практическая работа 3", "practice"), (OPD, "Практическая работа 1", "practice"),
    (OPD, "ЛК1", "lecture"), (OPD, "ЛК3", "lecture"), (UCH, "Лекция 1-2", "lecture"),
    (AD, "Практика 13", "practice"), (AD, "Практика 3", "practice"),
])]


@pytest.mark.parametrize("text,subjects,titles", [
    ("скинь практику 3 по основам предпр деят", [OPD], ["Практическая работа 3"]),
    ("нужна лекция 3 по основам предпр деят", [OPD], ["ЛК3"]),
    ("скинь лк1 по основам предпринимательской", [OPD], ["ЛК1"]),
    ("дай файлы по учетной деят", [UCH], ["Лекция 1-2"]),
    ("нужна практика 3 по анализу данных", [AD], ["Практика 3"]),      # не «Практика 13»
    ("скинь лекцию по предпр", [OPD, UCH], []),                         # ничья — переспросить
])
def test_find(text, subjects, titles):
    assert file_request.is_request(text)
    found, items = file_request.find(text, FILES)
    assert found == subjects
    assert [f["title"] for f in items] == titles


@pytest.mark.parametrize("text", ["как решить задачу про анализ данных", "когда следующая пара", "дай совет"])
def test_not_a_request(text):
    assert not file_request.is_request(text)


async def _feed(db, text):
    from database import add_file
    from handlers.files import router as files_router
    from handlers.solver import router as solver_router
    for f in FILES:
        await add_file(f["title"], f["subject"], f"TG{f['id']}", f["title"] + ".pdf", 0, category=f["category"])
    bot = Bot(token="123456:TEST-TOKEN-NOT-REAL-AAAAAAAAAAAAAAAAAAA", session=DocSession())
    dp = Dispatcher(storage=MemoryStorage())
    dp.include_router(files_router)
    dp.include_router(solver_router)
    try:
        msg = Message(message_id=5, date=0, chat=Chat(id=USER.id, type="private"), from_user=USER, text=text)
        await dp.feed_update(bot, Update(update_id=int(time.time()), message=msg))
    finally:
        files_router._parent_router = solver_router._parent_router = None
    return bot.session


@pytest.mark.asyncio
async def test_chat_request_sends_single_file(db, monkeypatch):
    import handlers.solver as solver

    async def no_ai(*a, **kw):
        raise AssertionError("просьба о файле не должна уходить к ИИ")

    monkeypatch.setattr(solver, "classify_intent", no_ai)
    session = await _feed(db, "скинь практику 3 по основам предпр деят")
    assert session.docs == [("SendDocument", "TG0", f"📄 <b>Практическая работа 3</b> ({OPD})")]


@pytest.mark.asyncio
async def test_chat_request_ambiguous_asks_subject(db, monkeypatch):
    import handlers.solver as solver
    monkeypatch.setattr(solver, "classify_intent", lambda *a: (_ for _ in ()).throw(AssertionError()))
    session = await _feed(db, "скинь лекцию по предпр")
    assert not session.docs
    assert any("По какому предмету" in t for t, _ in session.sent)


@pytest.mark.asyncio
async def test_download_link_is_signed_and_expires(db, monkeypatch):
    from types import SimpleNamespace
    from io import BytesIO
    from fastapi.testclient import TestClient
    import webapp.server as server
    from database import add_file
    from tests.test_webapp_home import BOT_TOKEN, _make_init_data
    fid = await add_file("ЛК1", OPD, "TGF", "Основы ЛК1.pdf", 0)

    class FakeBot:
        async def get_file(self, file_id):
            assert file_id == "TGF"
            return SimpleNamespace(file_path="documents/file_1.pdf")

        async def download_file(self, path):
            return BytesIO(b"%PDF-1.4 test")

    monkeypatch.setattr(server, "BOT_TOKEN", BOT_TOKEN)
    monkeypatch.setattr(server, "WEBAPP_URL", "https://app.example")
    monkeypatch.setattr(server, "tg_bot", lambda: FakeBot())
    c, headers = TestClient(server.app), {"X-Telegram-Init-Data": _make_init_data()}
    link = c.post(f"/api/files/{fid}/link", headers=headers).json()
    assert link["file_name"] == "Основы ЛК1.pdf"
    assert link["url"].startswith("https://app.example/dl/")
    path = link["url"].removeprefix("https://app.example")
    resp = c.get(path)                                   # без initData — по подписи
    assert resp.status_code == 200 and resp.content == b"%PDF-1.4 test"
    assert "attachment" in resp.headers["content-disposition"]
    assert c.get(path.replace("sig=", "sig=0")).status_code == 403
    monkeypatch.setattr(time, "time", lambda: 4102444800.0)  # 2100 год — ссылка протухла
    assert c.get(path).status_code == 403
