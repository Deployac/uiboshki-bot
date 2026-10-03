"""Посты канала бота (channel_posts.py, /channel у старосты): загрузка из
папок, выбор формата отправки, превью старосте и публикация по кнопке."""
import time
from types import SimpleNamespace

import pytest
from aiogram import Bot, Dispatcher
from aiogram.client.session.base import BaseSession
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import CallbackQuery, Chat, Message, Update, User

import channel_posts
import config
from tests.conftest import STAROSTA_ID


def _post(root, name, html, images=()):
    d = root / name
    d.mkdir(parents=True)
    (d / "post.html").write_text(html, encoding="utf-8")
    for i, img in enumerate(images):
        from PIL import Image
        Image.new("RGB", (86, 186 if i % 2 == 0 else 82), (20, 20, 30)).save(d / img)
    return d


def test_load_posts_order_title_and_images(tmp_path):
    _post(tmp_path, "02-pause", "<b>Пауза</b>\nтекст", ["10.png", "2.png", "1.jpg"])
    _post(tmp_path, "01-start", "<b>Как всё <i>началось</i></b>\n<blockquote expandable>подробнее</blockquote>")
    (tmp_path / "03-empty").mkdir()                                            # без post.html — не пост
    posts = channel_posts.load_posts(tmp_path)
    assert [p["slug"] for p in posts] == ["01-start", "02-pause"]
    assert posts[0]["title"] == "Как всё началось" and posts[0]["images"] == []
    assert [p.name for p in posts[1]["images"]] == ["1.jpg", "2.png", "10.png"]    # 10 — после 2
    assert channel_posts.visible_len("<b>a&amp;b</b>") == 3
    assert channel_posts.check({"html": "x" * 4097, "images": []}).startswith("текст 4097")


class FakeBot:
    def __init__(self):
        self.calls = []

    async def send_message(self, chat_id, text, link_preview_options=None, **kw):
        self.calls.append(("message", chat_id, text, link_preview_options))
        return SimpleNamespace(message_id=len(self.calls))

    async def send_photo(self, chat_id, photo, caption=None, **kw):
        self.calls.append(("photo", chat_id, caption, photo))
        return SimpleNamespace(message_id=len(self.calls))


@pytest.mark.asyncio
async def test_send_post_is_one_message(tmp_path):
    """Пост — одно сообщение (одно «Прокомментировать»): живой случай 04.10 —
    длинный пост с картинкой выходил двумя сообщениями, фото и текст отдельно."""
    short, long = "<b>Коротко</b>", "<b>Длинно</b>\n" + "слово " * 300
    _post(tmp_path, "a", short)
    _post(tmp_path, "b", short, ["1.png", "2.png"])
    _post(tmp_path, "c", long, ["1.png", "2.png", "3.png"])
    posts = {p["slug"]: p for p in channel_posts.load_posts(tmp_path)}
    bot = FakeBot()
    assert await channel_posts.send_post(bot, "@ch", posts["a"], "https://app.example") == [1]
    assert bot.calls[0][3].is_disabled                                          # без картинок — без превью
    assert await channel_posts.send_post(bot, "@ch", posts["b"], "https://app.example") == [2]
    assert bot.calls[1][:3] == ("photo", "@ch", short)                          # короткий — подписью к обложке
    assert await channel_posts.send_post(bot, "@ch", posts["c"], "https://app.example/") == [3]
    kind, _, text, lp = bot.calls[2]
    assert kind == "message" and text == long.strip()                                 # длинный — тоже одно сообщение,
    assert lp.url == channel_posts.cover_url("https://app.example", posts["c"])  # обложка — превью над текстом
    assert lp.url.startswith("https://app.example/chimg/c.jpg?v=") and lp.prefer_large_media and lp.show_above_text
    # без WEBAPP_URL отдать обложку по ссылке некому — как раньше, двумя сообщениями
    ids = await channel_posts.send_post(bot, "@ch", posts["c"])
    assert ids == [4, 5] and [c[0] for c in bot.calls[3:]] == ["photo", "message"]


def test_cover_one_image_from_many(tmp_path):
    from io import BytesIO
    from PIL import Image
    _post(tmp_path, "one", "<b>x</b>", ["1.png"])
    _post(tmp_path, "three", "<b>x</b>", ["1.png", "2.png", "3.png"])
    one, three = channel_posts.load_posts(tmp_path)
    w1, h1 = Image.open(BytesIO(channel_posts.cover_jpeg(one))).size
    w3, h3 = Image.open(BytesIO(channel_posts.cover_jpeg(three))).size
    assert w1 == h1 == h3 and w3 > h3                                           # один скрин — квадрат, три — шире
    key = channel_posts.cover_key(one)
    (tmp_path / "one" / "1.png").write_bytes((tmp_path / "three" / "2.png").read_bytes())
    assert channel_posts.cover_key(channel_posts.load_posts(tmp_path)[0]) != key  # новая картинка — новая ссылка
    assert channel_posts.check({"html": "x", "images": [1] * 5})


def test_cover_route(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from webapp.server import app
    _post(tmp_path, "01-start", "<b>x</b>", ["1.png"])
    _post(tmp_path, "02-text", "<b>x</b>")
    monkeypatch.setattr(channel_posts, "POSTS_DIR", tmp_path)
    c = TestClient(app)
    r = c.get("/chimg/01-start.jpg?v=abc")                                      # Telegram — без initData
    assert r.status_code == 200 and r.headers["content-type"] == "image/jpeg" and r.content[:2] == b"\xff\xd8"
    assert c.get("/chimg/02-text.jpg").status_code == 404                       # пост без картинок
    assert c.get("/chimg/nope.jpg").status_code == 404


@pytest.mark.asyncio
async def test_published_marks(db):
    assert await channel_posts.published() == {}
    await channel_posts.mark_published("01-start", [5, 6])
    assert (await channel_posts.published())["01-start"]["ids"] == [5, 6]
    assert channel_posts.post_link("@uiboshki_dev", 5) == "https://t.me/uiboshki_dev/5"
    assert channel_posts.post_link("-100123", 5) == ""


def test_channel_id_from_url():
    assert config.channel_id_from("", "https://t.me/uiboshki_dev") == "@uiboshki_dev"
    assert config.channel_id_from("-100777", "https://t.me/uiboshki_dev") == "-100777"
    assert config.channel_id_from("", "https://t.me/+ewZzJ8yHHSFhYWRi") == ""      # приватная ссылка
    assert config.channel_id_from("", "") == ""


class Session(BaseSession):
    def __init__(self):
        super().__init__()
        self.sent = []          # (chat_id, text, кнопки)

    async def close(self):
        pass

    async def make_request(self, bot, method, timeout=None):
        name = type(method).__name__
        if name == "SendMessage":
            kb = method.reply_markup.inline_keyboard if method.reply_markup else []
            self.sent.append((method.chat_id, method.text, [b.callback_data for row in kb for b in row]))
            cid = method.chat_id if isinstance(method.chat_id, int) else -100
            return Message(message_id=len(self.sent), date=0, chat=Chat(id=cid, type="private"), text=method.text).as_(bot)
        if name in ("DeleteMessages", "PinChatMessage"):
            self.sent.append((method.chat_id, name, getattr(method, "message_ids", None) or [method.message_id]))
            return True
        if name in ("AnswerCallbackQuery", "EditMessageReplyMarkup"):
            return True
        raise NotImplementedError(name)

    async def stream_content(self, *a, **kw):
        yield b""


@pytest.mark.asyncio
async def test_channel_command_preview_and_publish(db, tmp_path, monkeypatch):
    from handlers import channel
    _post(tmp_path, "00-pinned", "<b>Здесь — как делается бот</b>")
    _post(tmp_path, "01-start", "<b>Как всё началось</b>\nтекст")
    _post(tmp_path, "02-practice", "<b>Проект по программированию</b>")
    monkeypatch.setattr(channel_posts, "POSTS_DIR", tmp_path)
    monkeypatch.setattr(config, "CHANNEL_ID", "@uiboshki_dev")
    bot = Bot(token="123456:TEST-TOKEN-NOT-REAL-AAAAAAAAAAAAAAAAAAA", session=Session())
    dp = Dispatcher(storage=MemoryStorage())
    dp.include_router(channel.router)
    star, other = User(id=STAROSTA_ID, is_bot=False, first_name="S"), User(id=222, is_bot=False, first_name="A")

    async def feed(user, text=None, data=None):
        msg = Message(message_id=1, date=0, chat=Chat(id=user.id, type="private"), from_user=user, text=text or "x")
        upd = (Update(update_id=int(time.time() * 1e6) % 10**9, message=msg) if text else
               Update(update_id=int(time.time() * 1e6) % 10**9,
                      callback_query=CallbackQuery(id="1", from_user=user, chat_instance="c", data=data, message=msg)))
        await dp.feed_update(bot, upd)

    try:
        await feed(other, "/channel")
        assert bot.session.sent[-1][1] == "❌ Только для старосты."
        await feed(other, data="chan:pub:01-start")                              # чужая кнопка — ничего в канал
        assert not any(c == "@uiboshki_dev" for c, _, _ in bot.session.sent)

        await channel_posts.mark_published("00-pinned", [1])
        await feed(star, "/channel")
        texts = [t for _, t, _ in bot.session.sent]
        assert any("Посты канала" in t and "@uiboshki_dev" in t for t in texts)
        assert texts[-2] == "<b>Как всё началось</b>\nтекст"                      # превью старосте — как в канале
        assert bot.session.sent[-1][2] == ["chan:pub:01-start", "chan:next:01-start"]

        await feed(star, data="chan:pub:01-start")
        assert [c for c, _, _ in bot.session.sent].count("@uiboshki_dev") == 1
        assert "01-start" in await channel_posts.published()
        assert "t.me/uiboshki_dev/" in bot.session.sent[-1][1]
        await feed(star, data="chan:pub:01-start")                               # второй раз — не дублирует
        assert [c for c, _, _ in bot.session.sent].count("@uiboshki_dev") == 1

        await feed(star, "/channel")                                             # следующий — уже второй пост
        assert bot.session.sent[-2][1] == "<b>Проект по программированию</b>"

        # перевыпуск: убрать всё, что бот выпустил, и выпустить заново
        await feed(other, "/channel redo")
        await feed(other, data="chan:redo:yes")
        assert not any(t == "DeleteMessages" for _, t, _ in bot.session.sent)
        await feed(star, "/channel redo")
        assert bot.session.sent[-1][2] == ["chan:redo:yes"]
        before = sorted(i for v in (await channel_posts.published()).values() for i in v["ids"])
        await feed(star, data="chan:redo:yes")
        deleted = [(c, sorted(ids)) for c, t, ids in bot.session.sent if t == "DeleteMessages"]
        assert deleted == [("@uiboshki_dev", before)] and len(before) == 2
        assert await channel_posts.published() == {}
        await feed(star, "/channel")                                             # снова с закрепа
        assert bot.session.sent[-2][1] == "<b>Здесь — как делается бот</b>"
        await feed(star, data="chan:pub:00-pinned")                              # закреп бот закрепляет сам
        assert any(c == "@uiboshki_dev" and t == "PinChatMessage" for c, t, _ in bot.session.sent)
    finally:
        channel.router._parent_router = None


@pytest.mark.asyncio
async def test_offer_next_after_deploy(db, tmp_path, monkeypatch):
    """После деплоя бот сам присылает старосте превью следующего поста —
    один раз на пост; в канал без кнопки ничего не уходит."""
    from handlers import channel
    _post(tmp_path, "01-start", "<b>Как всё началось</b>")
    _post(tmp_path, "17-attendance", "<b>Посещения без Пульса</b>")
    monkeypatch.setattr(channel_posts, "POSTS_DIR", tmp_path)
    monkeypatch.setattr(config, "CHANNEL_ID", "@uiboshki_dev")
    monkeypatch.setattr(config, "STAROSTA_ID", STAROSTA_ID)
    await channel_posts.mark_published("01-start", [1])
    bot = Bot(token="123456:TEST-TOKEN-NOT-REAL-AAAAAAAAAAAAAAAAAAA", session=Session())
    assert await channel.offer_next(bot) == "17-attendance"
    sent = bot.session.sent
    assert all(c == STAROSTA_ID for c, _, _ in sent)                       # только старосте, не в канал
    assert sent[1][1] == "<b>Посещения без Пульса</b>" and sent[-1][2][0] == "chan:pub:17-attendance"
    n = len(sent)
    assert await channel.offer_next(bot) is None and len(bot.session.sent) == n   # второй деплой — тишина
    monkeypatch.setattr(config, "CHANNEL_ID", "")
    assert await channel.offer_next(bot) is None                              # канал не задан — молчим
